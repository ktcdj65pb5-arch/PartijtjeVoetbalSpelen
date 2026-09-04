// Supabase Edge Function: stuurt een bevestigingsmail via Resend
// wanneer er een nieuwe rij in "reserveringen" wordt aangemaakt.
//
// Deploy met: supabase functions deploy send-confirmation --no-verify-jwt
// Zet de Resend-sleutel met: supabase secrets set RESEND_API_KEY=...
//
// SUPABASE_URL en SUPABASE_SERVICE_ROLE_KEY staan al automatisch klaar
// in elke Edge Function, die hoef je niet zelf te zetten.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Zodra partijtjevoetbal.nl geverifieerd is in Resend, kan dit adres gebruikt worden.
const AFZENDER = "S.V. Wissel <reservering@partijtjevoetbal.nl>";

const TIJDSBLOK_LABELS: Record<string, string> = {
  "10-11": "10:00\u201311:00",
  "11-12": "11:00\u201312:00",
};

serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record;
    if (!record || !record.email) {
      return new Response("Geen record of e-mailadres", { status: 400 });
    }

    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: speeldag } = await sb
      .from("speeldagen")
      .select("datum")
      .eq("id", record.speeldag_id)
      .single();

    const datumLabel = speeldag
      ? new Date(speeldag.datum + "T12:00:00").toLocaleDateString("nl-NL", {
          weekday: "long",
          day: "numeric",
          month: "long",
        })
      : "";

    const tijdsblokLabel = TIJDSBLOK_LABELS[record.tijdsblok] || record.tijdsblok;
    const veldLabel = record.veldtype === "half" ? "half veld" : "kwart veld";

    const html = `
      <p>Hoi ${record.naam},</p>
      <p>Je inschrijving bij S.V. Wissel is bevestigd:</p>
      <ul>
        <li><strong>Datum:</strong> ${datumLabel}</li>
        <li><strong>Tijd:</strong> ${tijdsblokLabel}</li>
        <li><strong>Veld:</strong> ${veldLabel}</li>
        <li><strong>Team:</strong> ${record.team}</li>
        <li><strong>Aantal deelnemers:</strong> ${record.aantal_deelnemers}</li>
        <li><strong>Doeltjes:</strong> ${record.doeltje}</li>
      </ul>
      <p>Locatie: SV Wissel, Ericaweg 6, Epe.</p>
      <p>Tot dan!<br>S.V. Wissel</p>
    `;

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: AFZENDER,
        to: record.email,
        subject: "Bevestiging: partijtje voetbal bij S.V. Wissel",
        html,
      }),
    });

    if (!emailRes.ok) {
      const errText = await emailRes.text();
      return new Response("E-mail versturen mislukt: " + errText, { status: 500 });
    }

    return new Response("OK", { status: 200 });
  } catch (e) {
    return new Response("Fout: " + (e as Error).message, { status: 500 });
  }
});
