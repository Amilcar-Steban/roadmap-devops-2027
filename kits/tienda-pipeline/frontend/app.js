const $ = (id) => document.getElementById(id);

async function cargar() {
  const r = await fetch("/api/productos");
  const datos = await r.json();
  $("estado").textContent = "Datos servidos desde: " + datos.origen;
  $("productos").replaceChildren(...datos.productos.map((p) => {
    const li = document.createElement("li");
    li.textContent = `${p.nombre} · ${p.precio.toFixed(2)} € · stock ${p.stock} `;
    const b = document.createElement("button");
    b.textContent = "Comprar 1";
    b.onclick = () => comprar(p.id);
    li.append(b);
    return li;
  }));
  $("total").textContent = (await (await fetch("/api/pedidos")).json()).total;
}

async function comprar(id) {
  const r = await fetch("/api/pedidos", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ producto_id: id, cantidad: 1 }),
  });
  if (!r.ok) alert((await r.json()).detail);
  cargar();
}

cargar().catch(() => { $("estado").textContent = "La API no responde"; });
