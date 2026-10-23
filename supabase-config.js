// F-Do’s – Supabase bağlantı bilgileri
// Kurulum rehberi 2. adım: Supabase → Project Settings → API Keys (ya da Data API)
// ekranındaki "Project URL" ve "anon / publishable" anahtarı tırnakların içine yapıştır.
// Bu anahtar gizli değildir; verini koruyan şey schema.sql'deki güvenlik kurallarıdır.
// "service_role" ya da "secret" anahtarını BURAYA ASLA YAZMA.
window.FDOS_SUPABASE = {
  url: "https://PROJE-ID.supabase.co",
  anonKey: "BURAYA_ANON_KEY"
};
