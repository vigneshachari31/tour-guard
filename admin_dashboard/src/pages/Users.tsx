import { useState } from "react";
import { api } from "../api";
import { useResource } from "../hooks";
import type { Page, Tourist } from "../types";
import { Badge, Heading, Notice, Table, Pager } from "../components/UI";
export default function Users() {
  const [offset, setOffset] = useState(0);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const data = useResource<Page<Tourist>>(
    `/users?offset=${offset}&search=${encodeURIComponent(query)}`,
  );
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  async function toggle(user: Tourist) {
    if (
      !window.confirm(
        `${user.is_active ? "Deactivate" : "Activate"} ${user.email}? ${user.is_active ? "Their current tokens will lose API access." : ""}`,
      )
    )
      return;
    setBusy(true);
    setError("");
    try {
      await api(`/users/${user.id}`, {
        method: "PATCH",
        body: { is_active: !user.is_active },
      });
      data.refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Heading eyebrow="ACCOUNT ADMINISTRATION" title="Tourist accounts" />
      <form
        className="search-form"
        onSubmit={(e) => {
          e.preventDefault();
          setQuery(search);
          setOffset(0);
        }}
      >
        <input
          aria-label="Search tourists"
          placeholder="Search name, email or tourist ID"
          value={search}
          maxLength={200}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button>Search</button>
      </form>
      <Notice error={error || data.error} />
      <section className="panel">
        <Table
          loading={data.loading && !data.data}
          rows={data.data?.items ?? []}
          columns={[
            {
              title: "Tourist",
              render: (u) => (
                <>
                  <strong>{u.full_name || "Name not provided"}</strong>
                  <small>{u.tourist_id}</small>
                </>
              ),
            },
            { title: "Email", render: (u) => u.email },
            { title: "Phone", render: (u) => u.phone_number || "Not provided" },
            {
              title: "Account",
              render: (u) => (
                <Badge>{u.is_active ? "Active" : "Inactive"}</Badge>
              ),
            },
            {
              title: "Action",
              render: (u) => (
                <button
                  className={u.is_active ? "danger" : ""}
                  disabled={busy}
                  onClick={() => toggle(u)}
                >
                  {u.is_active ? "Deactivate" : "Activate"}
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
      <p className="muted">
        Deactivation preserves account data and history. Administrator accounts
        are managed outside this view.
      </p>
    </>
  );
}
