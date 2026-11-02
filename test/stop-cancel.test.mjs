// Regression test: the panel's "stop" must cancel the Agent turn in the host,
// not just tear down this plugin's view of the stream.
//
//   node test/stop-cancel.test.mjs
//
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { PassThrough } from 'node:stream'

// Applied before importing the plugin: state.json lives under LOCALAPPDATA.
process.env.LOCALAPPDATA = mkdtempSync(join(tmpdir(), 'glance-test-'))

const { apply } = await import('../index.js')

const events = []
const stdinWrites = []

class AbortError extends Error {}

let followSignal

const ctx = {
  logger: () => ({ info() {}, warn() {}, error() {}, debug() {} }),
  effect: (fn) => fn(),
  commands: {
    register(options) {
      ctx.commandHandler = options.handler
    }
  },
  sessions: {
    get: () => ({ header: { cwd: process.cwd() } })
  },
  workingDirectory: { defaultDirectory: process.cwd() },
  sessionController: {
    async create() {
      events.push(['create'])
      return { sessionId: 'session-under-test' }
    },
    async inspect() {
      return { ok: true }
    },
    async prompt(request) {
      events.push(['prompt', request.sessionId])
    },
    async rename() {},
    async cancel(request) {
      events.push(['cancel', request.sessionId])
      return { accepted: true }
    },
    follow(request, signal) {
      events.push(['follow', request.address.sessionId])
      followSignal = signal
      return (async function* () {
        await new Promise((resolve, reject) => {
          if (signal.aborted) reject(new AbortError('aborted by stop'))
          else signal.addEventListener('abort', () => reject(new AbortError('aborted by stop')), { once: true })
        })
        yield { type: 'unreachable' }
      })()
    }
  },
  subprocess: {
    spawn() {
      const stdin = {
        destroyed: false,
        writableEnded: false,
        write(chunk) {
          stdinWrites.push(String(chunk))
          return true
        },
        end() {}
      }
      const stdout = new PassThrough()
      stdout.on('data', () => {})
      const stderr = new PassThrough()
      stderr.on('data', () => {})
      ctx.emit = (object) => stdout.write(JSON.stringify(object) + '\n')
      return {
        stdin,
        stdout,
        stderr,
        terminate() {},
        killed: false,
        exited: false,
        done: new Promise(() => {})
      }
    }
  },
  webServer: {
    register(route) {
      ctx.statusRoute = route
      return () => {}
    }
  }
}

// Drives the registered status route and returns its JSON body.
async function readStatus() {
  const route = ctx.statusRoute
  if (!route) return undefined
  const captured = {}
  const response = {
    status: 0,
    writeHead(status) {
      captured.status = status
    },
    end(body) {
      captured.body = body
    }
  }
  await route.handler({ method: 'GET' }, response)
  return captured
}

const failures = []
function check(label, condition, detail) {
  if (condition) {
    console.log(`  ok   ${label}`)
  } else {
    console.log(`  FAIL ${label}${detail === undefined ? '' : ` (${JSON.stringify(detail)})`}`)
    failures.push(label)
  }
}

apply(ctx)

const idleStatus = await readStatus()
check(
  'status route reports idle before start',
  idleStatus !== undefined && idleStatus.status === 200 && JSON.parse(idleStatus.body).running === false,
  idleStatus
)

const startPromise = ctx.commandHandler({ rawInput: '/glance on', agent: { id: 'agent-1' } })
await new Promise((resolve) => setTimeout(resolve, 30))
ctx.emit({ type: 'ready' })
const start = await startPromise
check('widget starts', start.ok !== false && start.kind !== 'error', start)

const runningStatus = await readStatus()
check(
  'status route reports running after start',
  runningStatus !== undefined && JSON.parse(runningStatus.body).running === true,
  runningStatus
)

ctx.emit({ type: 'capture', imageBase64: 'AAAA', note: '这是什么' })
await new Promise((resolve) => setTimeout(resolve, 80))

const kinds = () => events.map((entry) => entry[0])
check('capture reaches the session', kinds().includes('prompt'), kinds())
check('stream is followed', kinds().includes('follow'), kinds())

ctx.emit({ type: 'abort' })
await new Promise((resolve) => setTimeout(resolve, 120))

const promptCall = events.find((entry) => entry[0] === 'prompt')
const cancelCall = events.find((entry) => entry[0] === 'cancel')
check('host turn is cancelled', cancelCall !== undefined, kinds())
check(
  'cancel targets the analysis session',
  cancelCall !== undefined && promptCall !== undefined && cancelCall[1] === promptCall[1],
  { cancel: cancelCall, prompt: promptCall }
)
check('stream signal is aborted', Boolean(followSignal && followSignal.aborted))

const widgetMessages = stdinWrites
  .join('')
  .split('\n')
  .filter(Boolean)
  .map((line) => JSON.parse(line))
const stopped = widgetMessages.filter((message) => message.type === 'analysis-stopped')
check('panel is told exactly once', stopped.length === 1, widgetMessages.map((m) => m.type))

if (failures.length > 0) {
  console.log(`\n${failures.length} check(s) failed`)
  process.exit(1)
}
console.log('\nall checks passed')
process.exit(0)
