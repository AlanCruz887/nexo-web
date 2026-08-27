import type { PropsWithChildren, ReactNode } from "react";

import { Card } from "@/components/ui/card";
import { AuthLayout } from "@/layouts/auth-layout";

export function AuthCard({
  children,
  description,
  footer,
  title,
}: PropsWithChildren<{ description: string; footer?: ReactNode; title: string }>) {
  return (
    <AuthLayout>
      <Card className="border-border/70 p-6 sm:p-8">
        <h1 className="text-3xl font-semibold tracking-[-0.04em]">{title}</h1>
        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{description}</p>
        <div className="mt-6">{children}</div>
        {footer ? <div className="mt-6 border-t border-border pt-5 text-center text-sm text-muted-foreground">{footer}</div> : null}
      </Card>
    </AuthLayout>
  );
}
