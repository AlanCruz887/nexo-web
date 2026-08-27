import { Link } from "react-router-dom";

import { Button } from "@/components/ui/button";

export function NotFoundPage() {
  return (
    <main className="grid min-h-screen place-items-center px-4 text-center">
      <div>
        <p className="text-sm font-semibold text-primary">404</p>
        <h1 className="mt-2 text-3xl font-semibold">Esta página no existe</h1>
        <Button asChild className="mt-6"><Link to="/inicio">Volver a Nexo</Link></Button>
      </div>
    </main>
  );
}
