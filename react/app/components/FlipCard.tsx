import { useState, type ReactNode } from 'react'

/**
 * fragrance/react FlowerCard 의 flip 코어 이식 — perspective 600px,
 * preserve-3d + rotateY 180°, transform 0.5s (수치 동일, CSS 는 app.css).
 * hover(마우스) 또는 focus(터치·키보드) 동안 뒤집힌 상태 유지.
 */
export function FlipCard({ front, back }: { front: ReactNode; back: ReactNode }) {
  const [flipped, setFlipped] = useState(false)
  return (
    <div
      className="flip-card"
      tabIndex={0}
      onMouseEnter={() => setFlipped(true)}
      onMouseLeave={() => setFlipped(false)}
      onFocus={() => setFlipped(true)}
      onBlur={() => setFlipped(false)}
    >
      <div className={`flip-card-inner${flipped ? ' flipped' : ''}`}>
        <div className="flip-card-front">{front}</div>
        <div className="flip-card-back">{back}</div>
      </div>
    </div>
  )
}
