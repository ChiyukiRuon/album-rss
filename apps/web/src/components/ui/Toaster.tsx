import { CheckCircleIcon, InfoIcon, WarningCircleIcon, XIcon } from '@phosphor-icons/react'
import { cx } from '../../lib/cx'
import { dismissToast, toastStore } from './toast'
import styles from './Toaster.module.css'

const ICONS = {
  neutral: InfoIcon,
  success: CheckCircleIcon,
  warning: WarningCircleIcon,
}

export function Toaster() {
  const toasts = toastStore.use((list) => list)
  return (
    <div className={styles.region} role="status" aria-live="polite">
      {toasts.map((toast) => {
        const Icon = ICONS[toast.tone]
        return (
          <div key={toast.id} className={cx(styles.toast, styles[toast.tone])}>
            <Icon className={styles.icon} weight="fill" aria-hidden />
            <div className={styles.body}>
              <p className={styles.message}>{toast.message}</p>
              {toast.detail && <p className={styles.detail}>{toast.detail}</p>}
            </div>
            {toast.action && (
              <button
                type="button"
                className={styles.action}
                onClick={() => {
                  toast.action?.run()
                  dismissToast(toast.id)
                }}
              >
                {toast.action.label}
              </button>
            )}
            <button
              type="button"
              className={styles.close}
              aria-label="关闭提示"
              onClick={() => dismissToast(toast.id)}
            >
              <XIcon aria-hidden />
            </button>
          </div>
        )
      })}
    </div>
  )
}
