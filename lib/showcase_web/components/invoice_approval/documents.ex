defmodule ShowcaseWeb.InvoiceApproval.Components.Documents do
  @moduledoc """
  Stylized Romanian commercial documents — Contract, Aviz de însoțire,
  Factură — rendered as printable HTML/Tailwind cards. No PDF library
  needed; styled to look like the real paperwork an AP clerk works with.

  Each component accepts data assigns and produces a self-contained
  document view that can be embedded inline (in the bundle detail page)
  or shown full-screen in a printable view.
  """

  use Phoenix.Component

  # ── Contract ──────────────────────────────────────────────────────────
  attr :contract, :map, required: true, doc: "Showcase.InvoiceApproval.Schemas.Contract"
  attr :client, :map, required: true

  def contract_doc(assigns) do
    # Pull line items from the contract body directly. (Don't use an attr
    # default — it overrides the assign_new path and makes the table empty.)
    assigns = assign(assigns, :line_items, get_in(assigns.contract.body, ["line_items"]) || [])

    assigns =
      assigns
      |> assign(:obiect, contract_obiect(assigns.contract.name))
      |> assign(:total, contract_total(assigns.line_items))

    ~H"""
    <article class="bg-white p-12 border border-line shadow-sm font-body text-ink/90 mx-auto leading-relaxed" style="max-width: 820px;">
      <!-- Title -->
      <header class="text-center mb-10 pb-6 border-b border-ink/30">
        <p class="text-[10px] uppercase tracking-[0.3em] text-ink/50">Contract de furnizare</p>
        <h1 class="font-heading text-2xl font-bold tracking-tight mt-2">
          Nr. {@contract.contract_number || "CTR-2026-####"} / {fmt_date(@contract.valid_from)}
        </h1>
      </header>

      <!-- Parties section -->
      <section class="mb-6 text-sm">
        <h2 class="font-heading font-bold text-base mb-3">I. PĂRȚILE CONTRACTANTE</h2>
        <p class="mb-3 text-justify">
          Încheiat astăzi, <span class="font-mono">{fmt_date(@contract.valid_from)}</span>, între:
        </p>
        <p class="mb-3 text-justify pl-4">
          <span class="font-semibold">S.C. NEURONY DEMO S.R.L.</span>, cu sediul în Str. Furnizor nr. 100,
          Sector 1, București, înregistrată la Oficiul Registrului Comerțului sub nr.
          <span class="font-mono">J40/1234/2026</span>, având CUI <span class="font-mono">RO99887766</span>,
          cont bancar <span class="font-mono">RO00 INGB 0000 0000 0000 0000</span> deschis la ING Bank,
          reprezentată prin Administrator Ionescu Andrei, denumită în continuare <strong>FURNIZOR</strong>,
        </p>
        <p class="mb-3 pl-4">și</p>
        <p class="text-justify pl-4">
          <span class="font-semibold">{String.upcase(@client.name)}</span>, cu sediul în
          <span :if={@client.address}>{@client.address}</span><span :if={!@client.address}>—</span>,
          având CUI <span class="font-mono">{@client.vat_number || "—"}</span>,
          reprezentată prin Director General, denumită în continuare <strong>BENEFICIAR</strong>.
        </p>
      </section>

      <!-- Object -->
      <section class="mb-6 text-sm">
        <h2 class="font-heading font-bold text-base mb-3">II. OBIECTUL CONTRACTULUI</h2>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 1.</span> {@obiect}
        </p>
        <p class="text-justify">
          <span class="font-semibold">Art. 2.</span> Cantitățile, codurile și prețurile produselor
          ce fac obiectul prezentului contract sunt prevăzute în <strong>Anexa nr. 1</strong>,
          care face parte integrantă din prezentul contract.
        </p>
      </section>

      <!-- Value & price -->
      <section class="mb-6 text-sm">
        <h2 class="font-heading font-bold text-base mb-3">III. VALOAREA CONTRACTULUI ȘI PREȚURILE</h2>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 3.</span> Valoarea totală a contractului este de
          <strong>{fmt_money(@total)} {@contract.currency || "RON"}</strong>, fără TVA.
          La aceasta se adaugă TVA în cotă de 19%, calculată conform legislației fiscale în vigoare.
        </p>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 4.</span> Prețurile unitare convenite sunt cele prevăzute
          în Anexa nr. 1 și sunt exprimate în RON, fără TVA. Aceste prețuri rămân ferme pe toată
          durata de valabilitate a contractului.
        </p>
        <p class="text-justify">
          <span class="font-semibold">Art. 5.</span> Orice modificare a prețurilor convenite poate
          fi efectuată doar prin act adițional, semnat de ambele părți, cu o notificare prealabilă
          de minimum 30 de zile calendaristice.
        </p>
      </section>

      <!-- Payment -->
      <section class="mb-6 text-sm">
        <h2 class="font-heading font-bold text-base mb-3">IV. MODALITATEA DE PLATĂ</h2>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 6.</span> Plata produselor se efectuează prin transfer
          bancar, în termen de 30 de zile calendaristice de la data emiterii facturii fiscale.
        </p>
        <p class="text-justify">
          <span class="font-semibold">Art. 7.</span> Întârzierea la plată atrage penalități de
          0,1% pe zi din suma datorată, dar nu mai mult de valoarea sumei restante.
        </p>
      </section>

      <!-- Delivery -->
      <section class="mb-6 text-sm">
        <h2 class="font-heading font-bold text-base mb-3">V. CONDIȚII DE LIVRARE</h2>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 8.</span> Livrarea se face <strong>FRANCO depozit Beneficiar</strong>,
          în termen de maximum 5 zile lucrătoare de la confirmarea comenzii ferme.
        </p>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 9.</span> Fiecare livrare este însoțită obligatoriu de
          un <strong>aviz de însoțire a mărfii</strong>, conform legislației fiscale române.
          Factura se emite în termen de maximum 15 zile calendaristice de la livrare.
        </p>
        <p class="text-justify">
          <span class="font-semibold">Art. 10.</span> Recepția cantitativă și calitativă se face de
          către Beneficiar la momentul livrării. Eventualele reclamații se semnalează în scris în
          termen de 48 ore de la recepție.
        </p>
      </section>

      <!-- Quality & warranty -->
      <section class="mb-6 text-sm">
        <h2 class="font-heading font-bold text-base mb-3">VI. CALITATEA PRODUSELOR ȘI GARANȚIA</h2>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 11.</span> Furnizorul garantează că produsele livrate
          respectă standardele europene aplicabile (EN 1935 pentru balamale, EN 12209 pentru broaște,
          EN 1303 pentru cilindri) și sunt însoțite de declarația de conformitate CE.
        </p>
        <p class="text-justify">
          <span class="font-semibold">Art. 12.</span> Termenul de garanție este de <strong>24 de luni</strong>
          de la data livrării, pentru utilizare normală conform fișei tehnice a produsului.
        </p>
      </section>

      <!-- Force majeure & disputes -->
      <section class="mb-6 text-sm">
        <h2 class="font-heading font-bold text-base mb-3">VII. FORȚA MAJORĂ ȘI LITIGII</h2>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 13.</span> Niciuna dintre părți nu este răspunzătoare pentru
          neîndeplinirea obligațiilor contractuale dacă aceasta este cauzată de un eveniment de forță
          majoră, conform art. 1351 Cod Civil.
        </p>
        <p class="text-justify">
          <span class="font-semibold">Art. 14.</span> Orice litigiu izvorât din executarea prezentului
          contract se soluționează pe cale amiabilă. În caz contrar, competența aparține instanțelor
          judecătorești din municipiul București.
        </p>
      </section>

      <!-- Final clauses -->
      <section class="mb-8 text-sm">
        <h2 class="font-heading font-bold text-base mb-3">VIII. CLAUZE FINALE</h2>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 15.</span> Prezentul contract intră în vigoare la data
          semnării și este valabil de la <strong>{fmt_date(@contract.valid_from)}</strong> până la
          <strong>{fmt_date(@contract.valid_until)}</strong>.
        </p>
        <p class="text-justify mb-2">
          <span class="font-semibold">Art. 16.</span> Modificarea prezentului contract se poate face
          doar prin act adițional, semnat de ambele părți.
        </p>
        <p class="text-justify">
          <span class="font-semibold">Art. 17.</span> Prezentul contract a fost încheiat astăzi,
          <span class="font-mono">{fmt_date(@contract.valid_from)}</span>, în 2 (două) exemplare originale,
          câte unul pentru fiecare parte.
        </p>
      </section>

      <!-- Signatures -->
      <div class="grid grid-cols-2 gap-12 mt-10 mb-12">
        <div>
          <p class="text-xs font-bold uppercase tracking-wider text-ink/70 mb-1">FURNIZOR</p>
          <p class="text-xs text-ink/80 mb-12">S.C. Neurony Demo S.R.L.</p>
          <div class="border-t border-ink/40 pt-1 text-xs text-ink/50">Administrator · Ionescu Andrei</div>
          <div class="mt-1 text-xs text-ink/50">L.S.</div>
        </div>
        <div>
          <p class="text-xs font-bold uppercase tracking-wider text-ink/70 mb-1">BENEFICIAR</p>
          <p class="text-xs text-ink/80 mb-12">{@client.name}</p>
          <div class="border-t border-ink/40 pt-1 text-xs text-ink/50">Director General</div>
          <div class="mt-1 text-xs text-ink/50">L.S.</div>
        </div>
      </div>

      <!-- Page break visual: Annex starts on a new "page" -->
      <div class="my-12 border-t-2 border-dashed border-ink/20 text-center">
        <span class="inline-block bg-white px-3 -translate-y-2.5 text-[10px] uppercase tracking-widest text-ink/40">— pag. 2 —</span>
      </div>

      <!-- Annex with line items -->
      <section>
        <h2 class="font-heading text-lg font-bold mb-1">ANEXA NR. 1</h2>
        <p class="text-xs text-ink/60 mb-4">la Contractul de furnizare nr. {@contract.contract_number || "CTR-2026-####"} / {fmt_date(@contract.valid_from)}</p>

        <p class="font-heading text-sm font-semibold mb-3">Lista produselor contractate</p>

        <table class="w-full text-xs border-collapse">
          <thead class="bg-surface-lav-2 text-ink/70">
            <tr>
              <th class="text-left border border-line px-2 py-1.5">Nr.</th>
              <th class="text-left border border-line px-2 py-1.5">Cod produs</th>
              <th class="text-left border border-line px-2 py-1.5">Denumire</th>
              <th class="text-right border border-line px-2 py-1.5">U.M.</th>
              <th class="text-right border border-line px-2 py-1.5">Cant.</th>
              <th class="text-right border border-line px-2 py-1.5">Preț unit.</th>
              <th class="text-right border border-line px-2 py-1.5">Valoare</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{item, idx} <- Enum.with_index(@line_items, 1)} class="hover:bg-surface-lav-2/50">
              <td class="border border-line px-2 py-1.5">{idx}</td>
              <td class="border border-line px-2 py-1.5 font-mono">{item["sku"]}</td>
              <td class="border border-line px-2 py-1.5">{item["name"]}</td>
              <td class="border border-line px-2 py-1.5 text-right">buc</td>
              <td class="border border-line px-2 py-1.5 text-right">{item["qty"]}</td>
              <td class="border border-line px-2 py-1.5 text-right">{fmt_money(item["unit_price"])}</td>
              <td class="border border-line px-2 py-1.5 text-right font-mono">{fmt_money(line_value(item))}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="font-bold bg-surface-lav-2">
              <td colspan="6" class="border border-line px-2 py-2 text-right">TOTAL CONTRACT (fără TVA):</td>
              <td class="border border-line px-2 py-2 text-right font-mono">{fmt_money(@total)} {@contract.currency || "RON"}</td>
            </tr>
            <tr class="bg-surface-lav-2">
              <td colspan="6" class="border border-line px-2 py-2 text-right">TVA 19%:</td>
              <td class="border border-line px-2 py-2 text-right font-mono">{fmt_money(@total * 0.19)}</td>
            </tr>
            <tr class="font-bold bg-ink/5">
              <td colspan="6" class="border border-line px-2 py-2 text-right">TOTAL CU TVA:</td>
              <td class="border border-line px-2 py-2 text-right font-mono">{fmt_money(@total * 1.19)}</td>
            </tr>
          </tfoot>
        </table>

        <p class="text-xs text-ink/60 mt-4 italic">
          Prezenta Anexă face parte integrantă din Contractul de furnizare nr.
          {@contract.contract_number || "CTR-2026-####"} și a fost semnată odată cu acesta.
        </p>

        <div class="grid grid-cols-2 gap-12 mt-10">
          <div>
            <p class="text-xs font-bold uppercase tracking-wider text-ink/70 mb-1">FURNIZOR</p>
            <div class="mt-12 border-t border-ink/40 pt-1 text-xs text-ink/50">Semnătură și ștampilă</div>
          </div>
          <div>
            <p class="text-xs font-bold uppercase tracking-wider text-ink/70 mb-1">BENEFICIAR</p>
            <div class="mt-12 border-t border-ink/40 pt-1 text-xs text-ink/50">Semnătură și ștampilă</div>
          </div>
        </div>
      </section>
    </article>
    """
  end

  # Per-contract "object" paragraph — gives each client's contract a
  # distinct subject so they're not interchangeable.
  defp contract_obiect("Contract-cadru feronerie 2026"),
    do: "Furnizorul se obligă să livreze Beneficiarului produse de feronerie pentru tâmplărie PVC și aluminiu (mânere, balamale, colțare, biți de instalare, garnituri), conform specificațiilor tehnice ale producătorului, iar Beneficiarul se obligă să le recepționeze și să le plătească conform condițiilor stabilite în prezentul contract."

  defp contract_obiect("Acord furnizare cremoane 2026"),
    do: "Furnizorul se obligă să livreze Beneficiarului cremoane, broaște multipunct, mecanisme antiflambaj și accesorii de închidere pentru tâmplărie metalică profesională, conform fișelor tehnice anexate și a standardelor europene EN 12209 / EN 1303, iar Beneficiarul se obligă să le recepționeze și să achite contravaloarea acestora."

  defp contract_obiect("Contract balamale Q2 2026"),
    do: "Furnizorul se obligă să livreze Beneficiarului balamale și colțare de fixare pentru uși de exterior și interior, conform standardului EN 1935 (clasa de uzură 12), precum și prelungitoare și mecanisme antiflambaj, iar Beneficiarul se obligă să le recepționeze conform specificațiilor și să le plătească conform condițiilor de plată convenite."

  defp contract_obiect(_),
    do: "Furnizorul se obligă să livreze Beneficiarului produsele prevăzute în Anexa nr. 1, conform specificațiilor tehnice agreate, iar Beneficiarul se obligă să le recepționeze și să le plătească conform condițiilor stabilite în prezentul contract."

  # ── Aviz de însoțire a mărfii ─────────────────────────────────────────
  attr :delivery_notes, :map, required: true, doc: "JSONB blob from bundle.delivery_notes"
  attr :client, :map, required: true

  def aviz_doc(assigns) do
    ~H"""
    <article class="bg-white p-10 border border-line shadow-sm font-body text-ink mx-auto" style="max-width: 800px;">
      <header class="border-b-2 border-amber-700 pb-4 mb-6">
        <div class="flex items-start justify-between">
          <div>
            <p class="font-heading text-2xl font-bold tracking-tight">Neurony Demo SRL</p>
            <p class="text-xs text-ink/70 mt-1">Str. Furnizor nr. 100 · București · CUI: RO99887766</p>
          </div>
          <div class="text-right">
            <p class="text-[10px] uppercase tracking-widest text-amber-700 font-bold">Aviz de însoțire a mărfii</p>
            <p class="font-mono text-lg font-bold mt-1">{@delivery_notes["aviz_number"] || "AVZ-####"}</p>
            <p class="text-xs text-ink/70 mt-1">Data livrării: {@delivery_notes["delivery_date"] || "—"}</p>
          </div>
        </div>
      </header>

      <div class="grid grid-cols-2 gap-6 mb-6 text-sm">
        <div class="border border-line rounded-lg p-4">
          <p class="text-[10px] font-bold uppercase tracking-wider text-ink/50">Expeditor</p>
          <p class="font-semibold mt-1">Neurony Demo SRL</p>
          <p class="text-xs text-ink/70">CUI: RO99887766</p>
        </div>
        <div class="border border-line rounded-lg p-4">
          <p class="text-[10px] font-bold uppercase tracking-wider text-ink/50">Destinatar</p>
          <p class="font-semibold mt-1">{@client.name}</p>
          <p :if={@client.vat_number} class="text-xs text-ink/70">CUI: {@client.vat_number}</p>
          <p :if={@client.address} class="text-xs text-ink/70">{@client.address}</p>
        </div>
      </div>

      <p class="font-heading text-base font-bold mb-2">Produse livrate</p>
      <table class="w-full text-xs border-collapse">
        <thead class="bg-amber-50 text-amber-900">
          <tr>
            <th class="text-left border border-line px-2 py-1.5">Nr.</th>
            <th class="text-left border border-line px-2 py-1.5">Cod produs</th>
            <th class="text-right border border-line px-2 py-1.5">Cantitate</th>
            <th class="text-right border border-line px-2 py-1.5">Preț unit.</th>
            <th class="text-left border border-line px-2 py-1.5">Data livrării</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{item, idx} <- Enum.with_index(@delivery_notes["items"] || [], 1)} class="hover:bg-amber-50/30">
            <td class="border border-line px-2 py-1.5">{idx}</td>
            <td class="border border-line px-2 py-1.5 font-mono">{item["line_key"]}</td>
            <td class="border border-line px-2 py-1.5 text-right">{item["qty"]}</td>
            <td class="border border-line px-2 py-1.5 text-right">{fmt_money(item["unit_price"])}</td>
            <td class="border border-line px-2 py-1.5">{item["delivered_on"]}</td>
          </tr>
        </tbody>
      </table>

      <div class="grid grid-cols-3 gap-6 mt-10 pt-6 border-t border-line text-xs">
        <div>
          <p class="text-ink/70 mb-10">Întocmit (delegat)</p>
          <div class="border-t border-ink/40 pt-1 text-ink/50">Nume, prenume, semnătură</div>
        </div>
        <div>
          <p class="text-ink/70 mb-10">Predat</p>
          <div class="border-t border-ink/40 pt-1 text-ink/50">Semnătură</div>
        </div>
        <div>
          <p class="text-ink/70 mb-10">Primit</p>
          <div class="border-t border-ink/40 pt-1 text-ink/50">Semnătură destinatar</div>
        </div>
      </div>
    </article>
    """
  end

  # ── Factură ───────────────────────────────────────────────────────────
  attr :invoice, :map, required: true, doc: "JSONB blob from bundle.invoice"
  attr :client, :map, required: true

  def invoice_doc(assigns) do
    ~H"""
    <article class="bg-white p-10 border border-line shadow-sm font-body text-ink mx-auto" style="max-width: 800px;">
      <header class="border-b-2 border-purple pb-4 mb-6">
        <div class="flex items-start justify-between">
          <div>
            <p class="font-heading text-2xl font-bold tracking-tight">Neurony Demo SRL</p>
            <p class="text-xs text-ink/70 mt-1">Str. Furnizor nr. 100 · București · CUI: RO99887766</p>
          </div>
          <div class="text-right">
            <p class="text-[10px] uppercase tracking-widest text-purple font-bold">Factură fiscală</p>
            <p class="font-mono text-lg font-bold mt-1">{@invoice["invoice_number"] || "F-####"}</p>
            <p class="text-xs text-ink/70 mt-1">
              Data emiterii: {@invoice["issue_date"] || "—"}<br/>
              Scadență: {@invoice["due_date"] || "—"}
            </p>
          </div>
        </div>
      </header>

      <div class="grid grid-cols-2 gap-6 mb-6 text-sm">
        <div class="border border-line rounded-lg p-4">
          <p class="text-[10px] font-bold uppercase tracking-wider text-ink/50">Furnizor</p>
          <p class="font-semibold mt-1">Neurony Demo SRL</p>
          <p class="text-xs text-ink/70">CUI: RO99887766</p>
          <p class="text-xs text-ink/70">RC: J40/1234/2026</p>
          <p class="text-xs text-ink/70">Banca: ING Bank · RO00 INGB 0000 0000 0000 0000</p>
        </div>
        <div class="border border-line rounded-lg p-4">
          <p class="text-[10px] font-bold uppercase tracking-wider text-ink/50">Cumpărător</p>
          <p class="font-semibold mt-1">{@client.name}</p>
          <p :if={@client.vat_number} class="text-xs text-ink/70">CUI: {@client.vat_number}</p>
          <p :if={@client.address} class="text-xs text-ink/70">{@client.address}</p>
        </div>
      </div>

      <p class="font-heading text-base font-bold mb-2">Detalii factură</p>
      <table class="w-full text-xs border-collapse">
        <thead class="bg-purple/10 text-purple">
          <tr>
            <th class="text-left border border-line px-2 py-1.5">Nr.</th>
            <th class="text-left border border-line px-2 py-1.5">Cod</th>
            <th class="text-right border border-line px-2 py-1.5">Cant.</th>
            <th class="text-right border border-line px-2 py-1.5">Preț unit.</th>
            <th class="text-right border border-line px-2 py-1.5">Valoare</th>
            <th class="text-right border border-line px-2 py-1.5">TVA 19%</th>
            <th class="text-right border border-line px-2 py-1.5">Total</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{item, idx} <- Enum.with_index(@invoice["items"] || [], 1)} class="hover:bg-purple/5">
            <td class="border border-line px-2 py-1.5">{idx}</td>
            <td class="border border-line px-2 py-1.5 font-mono">{item["line_key"]}</td>
            <td class="border border-line px-2 py-1.5 text-right">{item["qty"]}</td>
            <td class="border border-line px-2 py-1.5 text-right">{fmt_money(item["unit_price"])}</td>
            <td class="border border-line px-2 py-1.5 text-right font-mono">{fmt_money(line_value(item))}</td>
            <td class="border border-line px-2 py-1.5 text-right text-ink/60">{fmt_money(line_value(item) * 0.19)}</td>
            <td class="border border-line px-2 py-1.5 text-right font-mono">{fmt_money(line_value(item) * 1.19)}</td>
          </tr>
        </tbody>
        <tfoot>
          <% subtotal = invoice_subtotal(@invoice["items"] || []) %>
          <tr class="bg-surface-lav-2">
            <td colspan="6" class="border border-line px-2 py-1.5 text-right">Subtotal:</td>
            <td class="border border-line px-2 py-1.5 text-right font-mono">{fmt_money(subtotal)}</td>
          </tr>
          <tr class="bg-surface-lav-2">
            <td colspan="6" class="border border-line px-2 py-1.5 text-right">TVA (19%):</td>
            <td class="border border-line px-2 py-1.5 text-right font-mono">{fmt_money(subtotal * 0.19)}</td>
          </tr>
          <tr class="font-bold bg-purple/10 text-purple">
            <td colspan="6" class="border border-line px-2 py-2 text-right">TOTAL DE PLATĂ:</td>
            <td class="border border-line px-2 py-2 text-right font-mono">{fmt_money(subtotal * 1.19)} RON</td>
          </tr>
        </tfoot>
      </table>

      <div class="mt-6 text-xs text-ink/70">
        <p><span class="font-semibold">Modalitate plată:</span> Transfer bancar</p>
        <p><span class="font-semibold">Termen plată:</span> {@invoice["due_date"] || "—"}</p>
      </div>

      <div class="grid grid-cols-3 gap-6 mt-10 pt-6 border-t border-line text-xs">
        <div>
          <p class="text-ink/70 mb-10">Întocmit</p>
          <div class="border-t border-ink/40 pt-1 text-ink/50">Reprezentant furnizor</div>
        </div>
        <div></div>
        <div>
          <p class="text-ink/70 mb-10">L.S.</p>
          <div class="border-t border-ink/40 pt-1 text-ink/50">Ștampilă</div>
        </div>
      </div>
    </article>
    """
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp fmt_date(nil), do: "—"
  defp fmt_date(%Date{} = d), do: Calendar.strftime(d, "%d.%m.%Y")
  defp fmt_date(other), do: to_string(other)

  defp fmt_money(nil), do: "—"
  defp fmt_money(n) when is_number(n), do: :io_lib.format("~.2f", [n * 1.0]) |> List.to_string()
  defp fmt_money(other), do: to_string(other)

  # Computes `qty * unit_price` for one line item with nil-tolerant defaults.
  # Used in templates where qty/unit_price may legitimately be missing (partial
  # ResilientJSONParser results, fresh user uploads with sparse JSONB, or a
  # malformed scenario fixture). Without this guard, the template would crash
  # the whole bundle page mid-pitch — see REVIEW.md BL-02.
  defp line_value(item) when is_map(item) do
    (item["qty"] || 0) * (item["unit_price"] || 0) * 1.0
  end

  defp line_value(_), do: 0.0

  defp contract_total(line_items) do
    Enum.reduce(line_items, 0.0, fn item, acc -> acc + line_value(item) end)
  end

  defp invoice_subtotal(items) do
    Enum.reduce(items, 0.0, fn item, acc -> acc + line_value(item) end)
  end
end
