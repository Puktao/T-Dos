// F-Do’s – yönetici işlemleri (yeni kullanıcı ekleme)
// Supabase → Edge Functions → Deploy a new function → Via Editor → adı: fdos-admin
// Bu dosyanın tamamını yapıştır → Deploy. Ayarlarda "Verify JWT" kapalı olsun;
// kimlik ve yönetici kontrolü aşağıda yapılıyor.
// service_role anahtarı Supabase tarafından sunucuda verilir; uygulamaya ya da depoya girmez.
import { createClient } from "jsr:@supabase/supabase-js@2";

const DEPTS = ["teknik", "kat", "resepsiyon", "satinalma", "mutfak"];
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Yalnızca POST" }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: auth, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !auth?.user) return json({ error: "Oturum geçersiz, yeniden giriş yap." }, 401);
  const { data: caller } = await admin.from("fdos_profiles").select("role").eq("user_id", auth.user.id).maybeSingle();
  if (caller?.role !== "admin") return json({ error: "Bu işlem yalnızca yönetici içindir." }, 403);

  const b = await req.json().catch(() => ({}));
  if (b.action !== "create") return json({ error: "Bilinmeyen işlem." }, 400);

  const email = String(b.email || "").trim().toLowerCase();
  const password = String(b.password || "");
  const name = String(b.name || "").trim().slice(0, 40);
  const dept = DEPTS.includes(b.dept) ? b.dept : null;
  const role = b.role === "admin" ? "admin" : "user";
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "E-posta adresi geçersiz." }, 400);
  if (password.length < 6) return json({ error: "Şifre en az 6 karakter olmalı." }, 400);
  if (!name) return json({ error: "Ad boş olamaz." }, 400);

  const { data, error } = await admin.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { name, dept },
  });
  if (error) {
    const m = /already|registered|exists/i.test(error.message) ? "Bu e-posta ile kayıtlı bir kullanıcı zaten var." : error.message;
    return json({ error: m }, 400);
  }
  const { error: pErr } = await admin.from("fdos_profiles")
    .upsert({ user_id: data.user.id, email, name, dept, role }, { onConflict: "user_id" });
  if (pErr) return json({ error: "Kullanıcı açıldı ama profil kaydedilemedi: " + pErr.message }, 500);
  return json({ ok: true, user_id: data.user.id });
});
