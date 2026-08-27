import type { ReactNode } from "react";

interface FormFieldProps {
  children: ReactNode;
  error?: string | undefined;
  hint?: string;
  id: string;
  label: string;
}

export function FormField({ children, error, hint, id, label }: FormFieldProps) {
  const descriptionId = error ? `${id}-error` : hint ? `${id}-hint` : undefined;
  return (
    <div className="space-y-2">
      <label className="block text-sm font-medium text-foreground" htmlFor={id}>
        {label}
      </label>
      <div aria-describedby={descriptionId}>{children}</div>
      {error ? (
        <p className="text-sm text-danger" id={`${id}-error`} role="alert">
          {error}
        </p>
      ) : hint ? (
        <p className="text-sm text-muted-foreground" id={`${id}-hint`}>
          {hint}
        </p>
      ) : null}
    </div>
  );
}
