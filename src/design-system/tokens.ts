export const designTokens = {
  breakpoint: { mobile: 0, tablet: 768, desktop: 1024, wide: 1280 },
  radius: { sm: 8, md: 12, lg: 16, xl: 20 },
  spacing: { section: 40, page: 32, card: 24 },
  zIndex: { navigation: 30, overlay: 50, toast: 70 },
  shadow: { card: "card", floating: "float" },
} as const;

export { motionTokens } from "@/design-system/motion";
