import type { CardTheme } from "@/types/database";

export function CardArtwork({ theme }: { theme: CardTheme }) {
  if (theme === "bbva_oro") return <BbvaGoldArtwork />;
  if (theme === "banamex_clasica" || theme === "banamex_joy") {
    return <BanamexArtwork variant={theme === "banamex_joy" ? "joy" : "clasica"} />;
  }
  if (theme === "nu") return <NuArtwork />;
  return <GenericArtwork />;
}

function BbvaGoldArtwork() {
  return <div aria-hidden="true" className="absolute inset-0 overflow-hidden">
    <div className="absolute inset-0 bg-[linear-gradient(112deg,rgba(255,255,255,.22)_0%,rgba(255,255,255,.04)_27%,rgba(79,56,20,.10)_58%,rgba(255,248,216,.16)_100%)]" />
    <div className="absolute inset-0 opacity-30 [background-image:repeating-linear-gradient(96deg,rgba(255,255,255,.12)_0,rgba(255,255,255,.12)_1px,transparent_1px,transparent_5px)]" />
    <svg className="absolute -right-8 -top-7 h-[84%] w-[58%] opacity-[0.16]" viewBox="0 0 220 180">
      <path d="M38 0h74L54 180H0L38 0Z" fill="#fff9de" />
      <path d="M129 0h42l-57 180H72L129 0Z" fill="#6d572d" />
      <path d="M188 0h32v180h-89L188 0Z" fill="#fffdf2" />
    </svg>
    <div className="absolute inset-x-8 bottom-0 h-px bg-[#604b23]/18" />
  </div>;
}

function BanamexArtwork({ variant }: { variant: "clasica" | "joy" }) {
  const isJoy = variant === "joy";
  return <div aria-hidden="true" className="absolute inset-0 overflow-hidden">
    <div className={isJoy ? "absolute inset-0 bg-[linear-gradient(118deg,rgba(255,255,255,.11),transparent_42%,rgba(0,62,106,.13))]" : "absolute inset-0 bg-[linear-gradient(118deg,rgba(255,255,255,.08),transparent_46%,rgba(105,0,29,.16))]"} />
    <svg className="absolute -bottom-[24%] -right-[9%] h-[112%] w-[78%]" viewBox="0 0 320 250">
      <g fill="none" stroke="white" strokeLinecap="round">
        <path d="M167 132C224 69 278 75 297 96c-35 1-65 20-91 58" opacity={isJoy ? ".48" : ".36"} strokeWidth="31" />
        <path d="M154 138C111 72 65 60 33 82c36 11 66 36 84 77" opacity={isJoy ? ".28" : ".30"} strokeWidth="34" />
        <path d="M166 143c48 8 83 38 94 73-42-13-78-14-113 0" opacity={isJoy ? ".22" : ".26"} strokeWidth="28" />
      </g>
      <circle cx="161" cy="137" fill="white" opacity={isJoy ? ".20" : ".24"} r="34" />
    </svg>
    <span className="absolute -left-10 bottom-8 size-36 rounded-full border border-white/10" />
  </div>;
}

function NuArtwork() {
  return <div aria-hidden="true" className="absolute inset-0 overflow-hidden">
    <div className="absolute inset-0 bg-[linear-gradient(125deg,rgba(255,255,255,.10),transparent_46%,rgba(36,3,57,.20))]" />
    <svg className="absolute -bottom-10 -right-7 h-44 w-64 opacity-20" viewBox="0 0 260 180">
      <path d="M0 150c46-84 91-93 135-29 42 61 84 47 125-43v102H0Z" fill="white" />
    </svg>
  </div>;
}

function GenericArtwork() {
  return <div aria-hidden="true" className="absolute inset-0 overflow-hidden">
    <div className="absolute inset-0 bg-[linear-gradient(128deg,rgba(255,255,255,.09),transparent_48%,rgba(5,20,51,.20))]" />
    <span className="absolute -right-20 -top-24 size-64 rounded-full border border-white/12" />
    <span className="absolute -bottom-28 right-16 size-52 rounded-full border border-white/8" />
  </div>;
}
