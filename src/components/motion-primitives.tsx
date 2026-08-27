import { motion, useReducedMotion } from "framer-motion";
import type { PropsWithChildren } from "react";

import { motionTokens } from "@/design-system/motion";

export function FadeIn({ children, delay = 0 }: PropsWithChildren<{ delay?: number }>) {
  const reduceMotion = useReducedMotion();
  return <motion.div animate={{ opacity: 1, y: 0 }} initial={reduceMotion ? false : { opacity: 0, y: 4 }} transition={{ delay: reduceMotion ? 0 : delay, duration: reduceMotion ? 0 : motionTokens.duration.normal, ease: motionTokens.ease.enter }}>{children}</motion.div>;
}

export function StaggerList({ children }: PropsWithChildren) {
  const reduceMotion = useReducedMotion();
  return <motion.div animate="show" initial={reduceMotion ? false : "hidden"} variants={{ hidden: {}, show: { transition: { staggerChildren: reduceMotion ? 0 : 0.035 } } }}>{children}</motion.div>;
}

export const staggerItem = {
  hidden: { opacity: 0, y: 4 },
  show: { opacity: 1, y: 0, transition: { duration: motionTokens.duration.normal, ease: motionTokens.ease.enter } },
};
