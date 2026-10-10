import { describe, expect, it, vi } from "vitest";
import {
  removeUnusedIcon,
  saveActionIcon,
  validateActionIcon,
} from "../lib/action-icons";
import type { ClinicSupabaseClient } from "../lib/supabase";

function mockClient({
  updateError = null as unknown,
  rows = [{ id: "action" }],
  uploadError = null as unknown,
} = {}) {
  const upload = vi.fn().mockResolvedValue({ error: uploadError });
  const remove = vi
    .fn()
    .mockResolvedValue({ data: [{ name: "old.png" }], error: null });
  const exists = vi.fn().mockResolvedValue({ data: true, error: null });
  const select = vi.fn().mockResolvedValue({ data: rows, error: updateError });
  const query = { eq: vi.fn(), is: vi.fn(), select };
  query.eq.mockReturnValue(query);
  query.is.mockReturnValue(query);
  const update = vi.fn().mockReturnValue(query);
  const client = {
    storage: { from: vi.fn().mockReturnValue({ upload, remove, exists }) },
    from: vi.fn().mockReturnValue({ update }),
  } as unknown as ClinicSupabaseClient;
  return { client, upload, remove, exists, update, select, query };
}

describe("action icons", () => {
  it("rejects large, empty, or unsupported files", () => {
    expect(() =>
      validateActionIcon({ type: "image/svg+xml", size: 1 }),
    ).toThrow();
    expect(() => validateActionIcon({ type: "image/png", size: 0 })).toThrow();
    expect(() =>
      validateActionIcon({ type: "image/png", size: 2097153 }),
    ).toThrow();
    expect(() =>
      validateActionIcon({ type: "image/png", size: 2097152 }),
    ).not.toThrow();
  });
  it("uploads a unique file, compares old path, then cleans old file", async () => {
    const m = mockClient();
    const cleanup = vi.fn().mockResolvedValue(undefined);
    await saveActionIcon(
      m.client,
      "clinic",
      "action",
      "old.png",
      new Blob(["image"]),
      cleanup,
    );
    const path = m.upload.mock.calls[0][0];
    expect(path).toMatch(/^clinic\/action\/[\w-]+\.png$/);
    expect(m.update).toHaveBeenCalledWith({ icon_storage_path: path });
    expect(m.query.eq).toHaveBeenCalledWith("icon_storage_path", "old.png");
    expect(cleanup).toHaveBeenCalledWith("old.png");
    expect(m.upload.mock.invocationCallOrder[0]).toBeLessThan(
      m.select.mock.invocationCallOrder[0],
    );
    expect(m.select.mock.invocationCallOrder[0]).toBeLessThan(
      cleanup.mock.invocationCallOrder[0],
    );
  });
  it("cleans a new upload after save failure, retaining the old file", async () => {
    const m = mockClient({ updateError: new Error("network") });
    const cleanup = vi.fn().mockResolvedValue(undefined);
    await expect(
      saveActionIcon(
        m.client,
        "clinic",
        "action",
        "old.png",
        new Blob(["image"]),
        cleanup,
      ),
    ).rejects.toThrow("network");
    expect(cleanup).toHaveBeenCalledWith(m.upload.mock.calls[0][0]);
    expect(cleanup).not.toHaveBeenCalledWith("old.png");
  });
  it("detects concurrent edits instead of overwriting", async () => {
    const m = mockClient({ rows: [] });
    const cleanup = vi.fn().mockResolvedValue(undefined);
    await expect(
      saveActionIcon(
        m.client,
        "clinic",
        "action",
        null,
        new Blob(["image"]),
        cleanup,
      ),
    ).rejects.toThrow("уже изменена");
    expect(m.query.is).toHaveBeenCalledWith("icon_storage_path", null);
    expect(cleanup).toHaveBeenCalledOnce();
  });
  it("does not save after upload failure", async () => {
    const m = mockClient({ uploadError: new Error("upload") });
    const cleanup = vi.fn();
    await expect(
      saveActionIcon(
        m.client,
        "clinic",
        "action",
        null,
        new Blob(["image"]),
        cleanup,
      ),
    ).rejects.toThrow("upload");
    expect(m.update).not.toHaveBeenCalled();
    expect(cleanup).not.toHaveBeenCalled();
  });
  it("clears a reference before cleanup without uploading", async () => {
    const m = mockClient();
    const cleanup = vi.fn().mockResolvedValue(undefined);
    await saveActionIcon(
      m.client,
      "clinic",
      "action",
      "old.png",
      null,
      cleanup,
    );
    expect(m.upload).not.toHaveBeenCalled();
    expect(m.update).toHaveBeenCalledWith({ icon_storage_path: null });
    expect(cleanup).toHaveBeenCalledWith("old.png");
  });
  it("reports removal filtered by permissions for later retry", async () => {
    const m = mockClient();
    m.remove.mockResolvedValue({ data: [], error: null });
    await expect(removeUnusedIcon(m.client, "old.png")).rejects.toThrow(
      "пока не удалён",
    );
  });
  it("finishes cleanup when a prior attempt already removed the file", async () => {
    const m = mockClient();
    m.remove.mockResolvedValue({ data: [], error: null });
    m.exists.mockResolvedValue({ data: false, error: null });
    await expect(
      removeUnusedIcon(m.client, "old.png"),
    ).resolves.toBeUndefined();
  });
});
