import type { InstallmentPlanSummary } from "@/types/database";

export function installmentPeriodLabel(statementDate: string | null, currentStatementDate: string) {
  if (!statementDate) return "Sin mensualidades pendientes";
  if (statementDate === currentStatementDate) return "Mensualidad de este periodo";
  return statementDate > currentStatementDate ? "Próxima mensualidad" : "Mensualidad pendiente";
}

export function installmentsForStatement(plans: InstallmentPlanSummary[], statementDate: string) {
  return plans.filter((plan) => plan.next_statement_date === statementDate && plan.current_installment_minor !== null);
}

export function installmentTotalForStatement(plans: InstallmentPlanSummary[], statementDate: string) {
  return installmentsForStatement(plans, statementDate).reduce(
    (total, plan) => total + BigInt(plan.current_installment_minor ?? "0"),
    0n,
  );
}

export function parseInstallmentSegmentDescription(description: string) {
  const match = description.match(/^(.*) · Mensualidad (\d+) de (\d+)$/);
  if (!match) return { description, progress: "MSI del periodo" };
  return { description: match[1], progress: `${match[2]} de ${match[3]}` };
}
