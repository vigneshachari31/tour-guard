import { useState } from "react";
import type { FormEvent } from "react";
import { api } from "../api";
import { useResource, date } from "../hooks";
import type { Page, Responder } from "../types";
import { Badge, Heading, Notice, Table, Pager } from "../components/UI";
const empty = {
  id: undefined as number | undefined,
  name: "",
  phone: "",
  email: "",
  role: "Mountain Rescue",
  status: "available",
};
export default function Responders() {
  const [offset, setOffset] = useState(0);
  const data = useResource<Page<Responder>>(
    `/responders?offset=${offset}`,
    15000,
  );
  const [form, setForm] = useState(empty);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await api("/responders", {
        method: "POST",
        body: { ...form, email: form.email || null },
      });
      setForm(empty);
      data.refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Heading eyebrow="FIELD OPERATIONS" title="Responder directory" />
      <Notice error={error || data.error} />
      <form className="panel form-grid" onSubmit={save}>
        <h2>{form.id ? "Edit responder" : "Register responder"}</h2>
        {(["name", "phone", "email", "role"] as const).map((key) => (
          <label key={key}>
            {key}
            <input
              value={form[key]}
              onChange={(e) => setForm({ ...form, [key]: e.target.value })}
              required={key !== "email"}
              type={key === "email" ? "email" : "text"}
              maxLength={key === "name" ? 200 : key === "email" ? 254 : 50}
            />
          </label>
        ))}
        <label>
          Availability
          <select
            value={form.status}
            onChange={(e) => setForm({ ...form, status: e.target.value })}
          >
            <option value="available">Available</option>
            <option value="unavailable">Unavailable</option>
          </select>
        </label>
        <div className="form-actions">
          <button className="primary" disabled={busy}>
            Save responder
          </button>
          {form.id && (
            <button type="button" onClick={() => setForm(empty)}>
              Cancel edit
            </button>
          )}
        </div>
      </form>
      <section className="panel">
        <Table
          loading={data.loading && !data.data}
          rows={data.data?.items ?? []}
          columns={[
            {
              title: "Responder",
              render: (r) => (
                <>
                  <strong>{r.name}</strong>
                  <small>{r.role}</small>
                </>
              ),
            },
            {
              title: "Contact",
              render: (r) => (
                <>
                  {r.phone}
                  <small>{r.email}</small>
                </>
              ),
            },
            { title: "Availability", render: (r) => <Badge>{r.status}</Badge> },
            {
              title: "Assignment history",
              render: (r) => (
                <details>
                  <summary>{r.assignments.length} recent assignments</summary>
                  {r.assignments.map((a) => (
                    <p key={a.id}>
                      SOS #{a.sos_event_id}: {a.status} · {date(a.created_at)}
                    </p>
                  ))}
                </details>
              ),
            },
            {
              title: "Action",
              render: (r) => (
                <button
                  disabled={r.status === "assigned"}
                  onClick={() => {
                    setForm({
                      id: r.id,
                      name: r.name,
                      phone: r.phone,
                      email: r.email ?? "",
                      role: r.role,
                      status: r.status,
                    });
                    window.scrollTo({ top: 0, behavior: "smooth" });
                  }}
                >
                  Edit
                </button>
              ),
            },
          ]}
        />
        <Pager
          total={data.data?.total ?? 0}
          offset={offset}
          setOffset={setOffset}
        />
      </section>
    </>
  );
}
