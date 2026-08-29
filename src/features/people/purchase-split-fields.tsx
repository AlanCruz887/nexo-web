import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { useContacts } from "@/hooks/use-contacts";
import { minorToDisplay, parseMoneyInput } from "@/lib/money";

type Allocation = { contact_id: string; amount: string };

export function PurchaseSplitFields({ amount, allocations, disabled, onAllocations, onPersonalAmount, onScope, personalAmount, scope }: {
  amount: string; allocations: Allocation[]; disabled?: boolean; personalAmount: string;
  scope: "self" | "other" | "shared"; onScope: (value: "self" | "other" | "shared") => void;
  onPersonalAmount: (value: string) => void; onAllocations: (value: Allocation[]) => void;
}) {
  const contacts = useContacts();
  const active = contacts.data?.filter((item) => item.is_active) ?? [];
  function selectScope(next: typeof scope) {
    onScope(next);
    if (next === "self") { onPersonalAmount(amount); onAllocations([]); return; }
    if (next === "other") { onPersonalAmount("0"); onAllocations([{ contact_id: active[0]?.id ?? "", amount }]); return; }
    onPersonalAmount(""); onAllocations([{ contact_id: active[0]?.id ?? "", amount: "" }]);
  }
  let remaining = "—";
  try { remaining = scope === "other" && allocations.length ? "0.00" : minorToDisplay(parseMoneyInput(amount || "0") - parseMoneyInput(personalAmount || "0") - allocations.reduce((sum, item) => sum + parseMoneyInput(item.amount || "0"), 0n)); } catch { /* keep placeholder */ }
  return <section className="space-y-4 rounded-2xl border border-border bg-surface-secondary/50 p-4">
    <div><p className="text-sm font-semibold">¿Para quién fue esta compra?</p><p className="mt-1 text-xs text-muted-foreground">Solo tu parte contará como gasto personal.</p></div>
    <div className="grid grid-cols-3 gap-1 rounded-xl bg-surface p-1">
      {(["self", "other", "shared"] as const).map((value) => <button className={`min-h-11 rounded-lg px-2 text-xs font-semibold ${scope === value ? "bg-primary-soft text-primary-strong" : "text-muted-foreground"}`} disabled={disabled} key={value} onClick={() => selectScope(value)} type="button">{value === "self" ? "Solo para mí" : value === "other" ? "Otra persona" : "Compartida"}</button>)}
    </div>
    {scope !== "self" ? <div className="space-y-3">
      {scope === "shared" ? <label className="block text-sm font-medium">Tu parte<Input className="mt-2" inputMode="decimal" onChange={(event) => onPersonalAmount(event.target.value)} placeholder="0.00" value={personalAmount} /></label> : null}
      {allocations.map((allocation, index) => <div className="grid grid-cols-[1fr_8rem_auto] gap-2" key={`${index}-${allocation.contact_id}`}>
        <Select aria-label={`Persona ${index + 1}`} onChange={(event) => onAllocations(allocations.map((item, itemIndex) => itemIndex === index ? { ...item, contact_id: event.target.value } : item))} value={allocation.contact_id}><option value="">Elige una persona</option>{active.map((contact) => <option disabled={allocations.some((item, itemIndex) => itemIndex !== index && item.contact_id === contact.id)} key={contact.id} value={contact.id}>{contact.name}</option>)}</Select>
        <Input aria-label={`Importe de persona ${index + 1}`} disabled={scope === "other"} inputMode="decimal" onChange={(event) => onAllocations(allocations.map((item, itemIndex) => itemIndex === index ? { ...item, amount: event.target.value } : item))} placeholder="0.00" value={scope === "other" ? amount : allocation.amount} />
        {scope === "shared" && allocations.length > 1 ? <Button aria-label="Quitar persona" onClick={() => onAllocations(allocations.filter((_, itemIndex) => itemIndex !== index))} size="icon" type="button" variant="ghost"><Trash2 className="size-4" /></Button> : <span />}
      </div>)}
      {scope === "shared" ? <Button disabled={!active.some((contact) => !allocations.some((item) => item.contact_id === contact.id))} onClick={() => onAllocations([...allocations, { contact_id: active.find((contact) => !allocations.some((item) => item.contact_id === contact.id))?.id ?? "", amount: "" }])} size="sm" type="button" variant="ghost"><Plus className="size-4" />Agregar persona</Button> : null}
      {active.length === 0 ? <p className="text-sm text-warning">Primero agrega una persona desde Personas.</p> : null}
      <p className={`text-xs ${remaining === "0.00" ? "text-success" : "text-muted-foreground"}`}>Por distribuir: ${remaining}</p>
    </div> : null}
  </section>;
}
