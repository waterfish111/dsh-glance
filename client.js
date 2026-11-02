window.__ModuleLoader__.load({
  id: '@local/dsh-glance',
  factory(require) {
    const React = require('react');
    const h = React.createElement;

    const NS = 'glance';

    const DICTS = {
      en: {
        'button.label': 'Glance',
        'button.text': 'Glance',
        'button.running': 'Running',
        'button.starting': 'Starting…',
        'button.hintIdle': 'Start the capture widget and send any selected region to the multimodal model.',
        'button.hintRunning': 'The capture widget is running. Right-click the floating ball to change its look or close it.',
        'button.hintStarting': 'Starting the capture widget…',
        'error.binding': 'The conversation is not ready yet.',
        'error.command': 'The command could not run. Is the plugin enabled?'
      },
      zh: {
        'button.label': '一瞥',
        'button.text': '一瞥',
        'button.running': '运行中',
        'button.starting': '启动中…',
        'button.hintIdle': '启动悬浮球，框选任意区域交给多模态模型。',
        'button.hintRunning': '悬浮球正在运行；右键悬浮球可更换外观或关闭。',
        'button.hintStarting': '正在启动悬浮球…',
        'error.binding': '当前会话还未就绪，请稍后再试。',
        'error.command': '命令执行失败，插件可能未启用。'
      }
    };
    DICTS['zh-CN'] = DICTS.zh;

    let translate = (key) => key;
    let sessionsService;

    // The button is a launcher: it never claims to know whether the widget is
    // still alive, it only remembers that this page started it. Clicking again
    // re-runs the command, which is a no-op when the widget is already up.
    const store = { sessionId: null, busy: false, running: false, error: '' };
    const listeners = new Set();

    function emit() {
      for (const listener of Array.from(listeners)) listener();
    }

    function setStore(patch) {
      Object.assign(store, patch);
      emit();
    }

    function useStore() {
      const [, force] = React.useState(0);
      React.useEffect(() => {
        const listener = () => force((value) => value + 1);
        listeners.add(listener);
        return () => {
          listeners.delete(listener);
        };
      }, []);
      return store;
    }

    function dotStyle(running, busy) {
      return {
        flex: 'none',
        width: 6,
        height: 6,
        borderRadius: '50%',
        background: running ? 'var(--dsw-alias-brand-primary)' : 'var(--dsw-alias-state-idle-primary)',
        opacity: busy ? 0.5 : 1,
        transition: 'background 150ms ease, opacity 150ms ease'
      };
    }

    function GlanceButton(props) {
      const snapshot = useStore();
      const [hovered, setHovered] = React.useState(false);
      const sessionId = props ? props.sessionId : undefined;
      const t = translate;
      const busy = snapshot.busy;
      const running = snapshot.running;

      React.useEffect(() => {
        if (!sessionId) return undefined;
        setStore({ sessionId });
        return () => {
          if (store.sessionId === sessionId) setStore({ sessionId: null });
        };
      }, [sessionId]);

      const start = async () => {
        if (busy || !sessionId) return;
        let binding;
        try {
          binding = sessionsService.binding(sessionId);
        } catch {
          binding = undefined;
        }
        if (!binding) {
          setStore({ error: t('error.binding') });
          return;
        }
        setStore({ busy: true, error: '' });
        try {
          const result = await binding.session.command('/glance on');
          const matched = Boolean(result && result.ok === true && result.value && result.value.matched);
          if (!matched) {
            setStore({ busy: false, running: false, error: t('error.command') });
            return;
          }
          setStore({ busy: false, running: true, error: '' });
        } catch (error) {
          setStore({
            busy: false,
            running: false,
            error: error && error.message ? error.message : t('error.command')
          });
        }
      };

      const title = snapshot.error
        ? snapshot.error
        : busy
          ? t('button.hintStarting')
          : running
            ? t('button.hintRunning')
            : t('button.hintIdle');

      return h(
        'button',
        {
          type: 'button',
          'aria-label': t('button.label'),
          title,
          disabled: busy,
          onClick: start,
          onMouseEnter: () => setHovered(true),
          onMouseLeave: () => setHovered(false),
          style: {
            display: 'inline-flex',
            alignItems: 'center',
            gap: 6,
            height: 26,
            padding: '0 9px',
            border: '1px solid ' + (hovered ? 'var(--dsw-alias-border-l1)' : 'transparent'),
            borderRadius: 999,
            background: hovered ? 'var(--dsw-alias-bg-layer-1)' : 'transparent',
            color: running ? 'var(--dsw-alias-label-primary)' : 'var(--dsw-alias-label-secondary)',
            font: 'inherit',
            fontSize: 12,
            lineHeight: 1,
            cursor: busy ? 'progress' : 'pointer',
            userSelect: 'none',
            whiteSpace: 'nowrap',
            opacity: busy ? 0.7 : 1,
            transition: 'background 120ms ease, border-color 120ms ease, color 120ms ease'
          }
        },
        h('span', { 'aria-hidden': true, style: dotStyle(running, busy) }),
        h('span', { 'aria-hidden': true }, busy ? t('button.starting') : t('button.text')),
        running && !busy
          ? h(
              'span',
              {
                'aria-hidden': true,
                style: { fontSize: 11, color: 'var(--dsw-alias-label-secondary)' }
              },
              t('button.running')
            )
          : null
      );
    }

    return {
      inject: ['slots', 'sessions', 'locale'],
      apply(ctx) {
        sessionsService = ctx.sessions;
        translate = ctx.locale.bind(NS);

        for (const locale of Object.keys(DICTS)) {
          ctx.effect(() => ctx.locale.register(NS, locale, DICTS[locale]));
        }

        ctx.on('locale/change', () => emit());

        ctx.slots.inject('conversation.session.header.utilities', () =>
          ctx.slots.register(
            {
              name: 'conversation.session.header.utilities',
              id: 'glance-toggle',
              order: 20,
              label: () => translate('button.label')
            },
            GlanceButton
          )
        );
      }
    };
  }
});
