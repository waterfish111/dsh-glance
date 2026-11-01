window.__ModuleLoader__.load({
  id: '@local/dsh-glance',
  factory(require) {
    const React = require('react');
    const h = React.createElement;

    const NS = 'glance';
    const ENABLED_KEY = 'dsh-glance.enabled';

    const DICTS = {
      en: {
        'toggle.label': 'Glance',
        'toggle.on': 'Glance is on. Click to stop the capture widget.',
        'toggle.off': 'Start the capture widget and send any selected region to the multimodal model.',
        'toggle.busyText': 'Starting...',
        'toggle.busy': 'Starting the capture widget...',
        'error.binding': 'The conversation is not ready yet.',
        'error.command': 'The command could not run. Is the plugin enabled?'
      },
      zh: {
        'toggle.label': '一瞥',
        'toggle.on': '一瞥已开启，点击关闭抓屏小部件',
        'toggle.off': '开启抓屏小部件，框选任意区域交给多模态模型',
        'toggle.busyText': '启动中…',
        'toggle.busy': '正在启动抓屏小部件…',
        'error.binding': '当前会话还未就绪，请稍后再试。',
        'error.command': '命令执行失败，插件可能未启用。'
      }
    };
    DICTS['zh-CN'] = DICTS.zh;

    let translate = (key) => key;
    let sessionsService;

    const store = { enabled: false, sessionId: null, busy: false, error: '' };
    const listeners = new Set();

    function emit() {
      for (const listener of Array.from(listeners)) listener();
    }

    function setStore(patch) {
      Object.assign(store, patch);
      emit();
    }

    function readEnabled() {
      try {
        return window.localStorage.getItem(ENABLED_KEY) === '1';
      } catch {
        return false;
      }
    }

    function writeEnabled(value) {
      try {
        window.localStorage.setItem(ENABLED_KEY, value ? '1' : '0');
      } catch {
        /* Storage is optional; the switch still works for this page. */
      }
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

    function ToggleSwitch(props) {
      const snapshot = useStore();
      const [hovered, setHovered] = React.useState(false);
      const sessionId = props ? props.sessionId : undefined;
      const t = translate;
      const enabled = snapshot.enabled;
      const busy = snapshot.busy;

      React.useEffect(() => {
        if (!sessionId) return undefined;
        setStore({ sessionId });
        return () => {
          if (store.sessionId === sessionId) setStore({ sessionId: null });
        };
      }, [sessionId]);

      const toggle = async () => {
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
        const next = !store.enabled;
        setStore({ busy: true, error: '' });
        try {
          const result = await binding.session.command(`/glance ${next ? 'on' : 'off'}`);
          const matched = Boolean(result && result.ok === true && result.value && result.value.matched);
          if (!matched) {
            setStore({ busy: false, error: t('error.command') });
            return;
          }
          writeEnabled(next);
          setStore({ enabled: next, busy: false, error: '' });
        } catch (error) {
          setStore({
            busy: false,
            error: error && error.message ? error.message : t('error.command')
          });
        }
      };

      const title = snapshot.error
        ? snapshot.error
        : busy
          ? t('toggle.busy')
          : enabled
            ? t('toggle.on')
            : t('toggle.off');

      return h(
        'button',
        {
          type: 'button',
          role: 'switch',
          'aria-checked': enabled,
          'aria-label': t('toggle.label'),
          title,
          disabled: busy,
          onClick: toggle,
          onMouseEnter: () => setHovered(true),
          onMouseLeave: () => setHovered(false),
          style: {
            display: 'inline-flex',
            alignItems: 'center',
            gap: 7,
            height: 26,
            padding: '0 8px',
            border: '1px solid ' + (hovered ? 'var(--dsw-alias-border-l1)' : 'transparent'),
            borderRadius: 999,
            background: hovered ? 'var(--dsw-alias-bg-layer-1)' : 'transparent',
            color: enabled ? 'var(--dsw-alias-label-primary)' : 'var(--dsw-alias-label-secondary)',
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
        h('span', { 'aria-hidden': true }, busy ? t('toggle.busyText') : t('toggle.label')),
        h(
          'span',
          {
            'aria-hidden': true,
            style: {
              position: 'relative',
              flex: 'none',
              width: 30,
              height: 16,
              borderRadius: 999,
              background: enabled ? 'var(--dsw-alias-brand-primary)' : 'var(--dsw-alias-state-idle-primary)',
              transition: 'background 150ms ease'
            }
          },
          h('span', {
            style: {
              position: 'absolute',
              top: 2,
              left: enabled ? 16 : 2,
              width: 12,
              height: 12,
              borderRadius: '50%',
              background: 'var(--dsw-alias-label-primary)',
              boxShadow: '0 1px 2px color-mix(in srgb, var(--dsw-alias-bg-base) 45%, transparent)',
              transition: 'left 150ms ease'
            }
          })
        )
      );
    }

    return {
      inject: ['slots', 'sessions', 'locale'],
      apply(ctx) {
        sessionsService = ctx.sessions;
        store.enabled = readEnabled();
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
              label: () => translate('toggle.label')
            },
            ToggleSwitch
          )
        );
      }
    };
  }
});
