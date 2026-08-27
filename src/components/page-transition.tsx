import { motion, useReducedMotion } from "framer-motion";
import type { PropsWithChildren } from "react";

import { motionTokens } from "@/design-system/motion";

export function PageTransition({ children }: PropsWithChildren) {
  const reduceMotion = useReducedMotion();
  return (
    <motion.div
      initial={reduceMotion ? false : { opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: reduceMotion ? 0 : motionTokens.duration.normal, ease: motionTokens.ease }}
    >
      {children}
    </motion.div>
  );
}
