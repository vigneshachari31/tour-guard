with open('admin_dashboard/src/components/UI.tsx', 'r', encoding='utf-8') as f:
    text = f.read()

norm_text = text.replace('\r\n', '\n')

old_part = '''          {rows.length === 0 && (
            <tr>
              <td colSpan={columns.length} className="empty">
                {loading ? "Loading records?" : "No records found."}
              </td>
            </tr>
          )}'''

new_part = '''          {loading && (
            <tr>
              <td colSpan={columns.length} className="table-loading-cell">
                <div className="table-loader-box">
                  <div className="spinner-blue" />
                  <span>Loading records...</span>
                </div>
              </td>
            </tr>
          )}
          {!loading && rows.length === 0 && (
            <tr>
              <td colSpan={columns.length} className="empty">
                No records found.
              </td>
            </tr>
          )}'''

assert old_part in norm_text, 'old_part not found in UI.tsx'
norm_text = norm_text.replace(old_part, new_part, 1)

with open('admin_dashboard/src/components/UI.tsx', 'w', encoding='utf-8', newline='') as f:
    f.write(norm_text)
print('Updated UI.tsx successfully')

