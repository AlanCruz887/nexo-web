export const motionTokens = {
  duration: {
    instant: 0.12,
    fast: 0.17,
    normal: 0.23,
    slow: 0.36,
  },
  ease: {
    standard: [0.2, 0, 0, 1] as const,
    enter: [0.22, 1, 0.36, 1] as const,
    exit: [0.4, 0, 1, 1] as const,
  },
  spring: { damping: 30, stiffness: 360, mass: 0.8 },
} as const;
