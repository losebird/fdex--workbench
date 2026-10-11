import type { HeroBrandMarkOwnerProps } from '@deepseek-ai/dsh-client-ui-conversation/client'
import type { SidebarBrandMarkOwnerProps } from '@deepseek-ai/dsh-client-ui-sidebar/client'

type OfficialBrandMarkProps = HeroBrandMarkOwnerProps & SidebarBrandMarkOwnerProps
/** Square mark for sidebar / hero slots (favicon-style X). */
const FDE_X_MARK_SRC = '/ff-brand/favicon.svg'
const FDE_X_MARK_RADIUS = '20%'

/**
 * Render the FDE-X mark with the presentation requested by its host surface.
 * @param props - Host-supplied mark presentation.
 * @returns the shared FDE-X mark image.
 */
export function OfficialBrandMark({ size, className }: OfficialBrandMarkProps) {
  return (
    <img
      src={FDE_X_MARK_SRC}
      alt=""
      aria-hidden="true"
      width={size}
      height={size}
      className={className}
      style={{ objectFit: 'contain', borderRadius: FDE_X_MARK_RADIUS }}
    />
  )
}

/**
 * Render the FDE-X product name without its independently slotted mark.
 * @returns the exact confirmed product name.
 */
export function OfficialBrandName() {
  return <span>FDE-X</span>
}
