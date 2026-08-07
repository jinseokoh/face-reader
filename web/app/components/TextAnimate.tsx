import { motion, type Variants } from 'motion/react'

/**
 * magicui text-animate (https://magicui.design/docs/components/text-animate)
 * 의 custom motion variants 경로만 이식 — 문자 단위 분해 + variants 의
 * `show` 에 char index 를 custom 으로 전달해 stagger wave 를 만든다.
 * (원본은 tailwind + animation preset 포함 — 이 프로젝트는 plain CSS 라
 * 필요한 최소만 가져옴.)
 */
export function TextAnimate({
  children,
  className,
  variants,
}: {
  children: string
  className?: string
  variants: Variants
}) {
  return (
    <motion.span
      className={className}
      initial="hidden"
      animate="show"
      aria-label={children}
    >
      {Array.from(children).map((ch, i) => (
        <motion.span
          key={i}
          custom={i}
          variants={variants}
          aria-hidden="true"
          style={{ display: 'inline-block', whiteSpace: 'pre' }}
        >
          {ch}
        </motion.span>
      ))}
    </motion.span>
  )
}
