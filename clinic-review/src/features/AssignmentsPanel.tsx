import { FormEvent, useEffect, useState } from "react";

import { DetailedInstructionViewer } from "./DetailedInstructionViewer";
import type { DetailedInstruction } from "../lib/detailed-instruction";
import { AssignmentIcon } from "./AssignmentIcon";

import { assignmentHistoryLabel, groupAssignments } from "../lib/assignments";
import { assignmentCompletionView } from "../lib/completions";
import { publicErrorMessage } from "../lib/errors";
import { supabase } from "../lib/supabase";
import { Badge, EmptyState, Field } from "../ui/primitives";

export type AssignmentRow = {
  id: string;
  title: string;
  instruction: string | null;
  detailed_instruction: DetailedInstruction | null;
  start_date: string;
  end_date: string;
  status: "active" | "disabled";
  icon_storage_path: string | null;
};

export type CatalogOption = {
  id: string;
  title: string;
};

export type CompletionRow = {
  assignment_id: string;
  completed_on: string;
};

type Props = {
  treatmentId: string;
  treatmentActive: boolean;
  assignments: AssignmentRow[];
  completions: CompletionRow[];
  catalog: CatalogOption[];
  defaultDate: string;
  onChanged: () => Promise<void>;
};

export function AssignmentsPanel({
  treatmentId,
  treatmentActive,
  assignments,
  completions,
  catalog,
  defaultDate,
  onChanged,
}: Props) {
  const [preview, setPreview] = useState<{
    title: string;
    instruction: DetailedInstruction;
  } | null>(null);
  const [catalogItemId, setCatalogItemId] = useState(catalog[0]?.id ?? "");
  const [startDate, setStartDate] = useState(defaultDate);
  const [endDate, setEndDate] = useState(defaultDate);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (catalogItemId === "" && catalog[0] !== undefined) {
      setCatalogItemId(catalog[0].id);
    }
  }, [catalog, catalogItemId]);


  async function assign(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const { error: rpcError } = await supabase.rpc(
      "assign_catalog_item_to_treatment",
      {
        p_treatment_id: treatmentId,
        p_catalog_item_id: catalogItemId,
        p_start_date: startDate,
        p_end_date: endDate,
      },
    );
    setBusy(false);
    if (rpcError) {
      setError(publicErrorMessage(rpcError, "Не удалось назначить действие."));
      return;
    }
    await onChanged();
  }

  async function disable(assignmentId: string) {
    setBusy(true);
    const { error: updateError } = await supabase
      .from("action_assignments")
      .update({ status: "disabled" })
      .eq("id", assignmentId);
    setBusy(false);
    if (updateError) {
      setError(
        publicErrorMessage(updateError, "Не удалось отключить назначение."),
      );
      return;
    }
    await onChanged();
  }

  return (
    <section className="card">
      <h2 className="card-title">Назначения</h2>
      {error !== null ? <p className="error">{error}</p> : null}
      {treatmentActive ? (
        catalog.length === 0 ? (
          <p className="muted">
            Нет утверждённых пунктов каталога. Сначала утвердите формулировку.
          </p>
        ) : (
          <form className="form-grid" onSubmit={(event) => void assign(event)}>
            <Field label="Пункт каталога">
              <select
                value={catalogItemId}
                onChange={(event) => setCatalogItemId(event.target.value)}
              >
                {catalog.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.title}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="С">
              <input
                type="date"
                value={startDate}
                onChange={(event) => setStartDate(event.target.value)}
                required
              />
            </Field>
            <Field label="По">
              <input
                type="date"
                value={endDate}
                onChange={(event) => setEndDate(event.target.value)}
                required
              />
            </Field>
            <button type="submit" disabled={busy}>
              Назначить
            </button>
          </form>
        )
      ) : (
        <p className="muted">
          Назначения можно добавлять только в активном лечении.
        </p>
      )}

      <AssignmentSections
        assignments={assignments}
        completions={completions}
        today={defaultDate}
        treatmentActive={treatmentActive}
        busy={busy}
        onPreview={(assignment) => {
          if (assignment.detailed_instruction)
            setPreview({
              title: assignment.title,
              instruction: assignment.detailed_instruction,
            });
        }}
        onDisable={(assignmentId) => void disable(assignmentId)}
      />
      {preview && (
        <DetailedInstructionViewer
          title={preview.title}
          instruction={preview.instruction}
          onClose={() => setPreview(null)}
        />
      )}
    </section>
  );
}

function AssignmentSections({
  assignments,
  completions,
  today,
  treatmentActive,
  busy,
  onDisable,
  onPreview,
}: {
  assignments: AssignmentRow[];
  completions: CompletionRow[];
  today: string;
  treatmentActive: boolean;
  busy: boolean;
  onDisable: (assignmentId: string) => void;
  onPreview: (assignment: AssignmentRow) => void;
}) {
  const groups = groupAssignments(assignments, today);

  if (assignments.length === 0) {
    return <EmptyState title="Назначений пока нет" />;
  }

  return (
    <>
      <div className="assignment-section">
        <h3>Сейчас</h3>
        {groups.current.length === 0 ? (
          <p className="muted">На сегодня активных назначений нет.</p>
        ) : (
          groups.current.map((assignment) => {
            const view = assignmentCompletionView(
              completions,
              assignment.id,
              today,
            );
            return (
              <div key={assignment.id} className="assignment-item">
                <div className="row" style={{ alignItems: "center" }}>
                  <AssignmentIcon path={assignment.icon_storage_path} />
                  <h3 style={{ margin: 0 }}>{assignment.title}</h3>
                  <Badge tone={view.completedToday ? "success" : "warning"}>
                    Сегодня: {view.completedToday ? "выполнено" : "не отмечено"}
                  </Badge>
                </div>
                <p className="muted">
                  {assignment.start_date} — {assignment.end_date}
                </p>
                {assignment.instruction !== null ? (
                  <p>{assignment.instruction}</p>
                ) : null}
                {assignment.detailed_instruction && (
                  <InstructionLink onClick={() => onPreview(assignment)} />
                )}
                {treatmentActive ? (
                  <button
                    type="button"
                    className="secondary"
                    disabled={busy}
                    onClick={() => onDisable(assignment.id)}
                  >
                    Отключить
                  </button>
                ) : null}
                {view.historicalDates.length > 0 ? (
                  <p className="muted">
                    Отметки: {view.historicalDates.join(", ")}
                  </p>
                ) : null}
              </div>
            );
          })
        )}
      </div>

      {groups.upcoming.length > 0 ? (
        <div className="assignment-section">
          <h3>Ещё не начались</h3>
          {groups.upcoming.map((assignment) => (
            <div key={assignment.id} className="assignment-item">
              <div className="row" style={{ alignItems: "center" }}>
                <AssignmentIcon path={assignment.icon_storage_path} />
                <h3 style={{ margin: 0 }}>{assignment.title}</h3>
              </div>
              <p className="muted">
                {assignment.start_date} — {assignment.end_date}
              </p>
              {assignment.instruction !== null ? (
                <p>{assignment.instruction}</p>
              ) : null}
              {assignment.detailed_instruction && (
                <InstructionLink onClick={() => onPreview(assignment)} />
              )}
              {treatmentActive ? (
                <button
                  type="button"
                  className="secondary"
                  disabled={busy}
                  onClick={() => onDisable(assignment.id)}
                >
                  Отключить
                </button>
              ) : null}
            </div>
          ))}
        </div>
      ) : null}

      <div className="assignment-section">
        <h3>История</h3>
        {groups.history.length === 0 ? (
          <p className="muted">Прошедших назначений пока нет.</p>
        ) : (
          groups.history.map((group) => (
            <div key={group.title} className="assignment-item">
              <div className="row" style={{ alignItems: "center" }}>
                <AssignmentIcon path={group.icon_storage_path} />
                <h3 style={{ margin: 0 }}>{group.title}</h3>
              </div>
              <ul className="assignment-history">
                {group.items.map((assignment) => {
                  const marks = completions.filter(
                    (item) => item.assignment_id === assignment.id,
                  ).length;
                  return (
                    <li key={assignment.id}>
                      <span>
                        {assignment.start_date} — {assignment.end_date}
                        {marks > 0 ? ` · отметок ${marks}` : ""}
                      </span>
                      <Badge tone="neutral">
                        {assignmentHistoryLabel(assignment, today)}
                      </Badge>
                      {assignment.detailed_instruction && (
                        <InstructionLink
                          onClick={() => onPreview(assignment)}
                        />
                      )}
                    </li>
                  );
                })}
              </ul>
            </div>
          ))
        )}
      </div>
    </>
  );
}

function InstructionLink({ onClick }: { onClick: () => void }) {
  return (
    <div className="assignment-instruction-link">
      <Badge tone="info">Есть подробная инструкция</Badge>
      <button type="button" className="secondary" onClick={onClick}>
        Посмотреть
      </button>
    </div>
  );
}
