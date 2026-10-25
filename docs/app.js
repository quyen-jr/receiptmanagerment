const categories = [
  { name: 'Ăn uống', color: '#f07454', icon: '♨' },
  { name: 'Mua sắm', color: '#e5a73a', icon: '▱' },
  { name: 'Di chuyển', color: '#4b9986', icon: '◆' },
  { name: 'Hóa đơn', color: '#7567a7', icon: 'ϟ' },
  { name: 'Sức khỏe', color: '#82a85b', icon: '✚' },
  { name: 'Khác', color: '#8a8f89', icon: '•••' },
];

const sampleTransactions = [
  { id: 'demo-1', merchant: 'Highlands Coffee', amount: 89000, category: 'Ăn uống', date: '2026-10-25', note: 'Cà phê làm việc' },
  { id: 'demo-2', merchant: 'Grab', amount: 47000, category: 'Di chuyển', date: '2026-10-24', note: '' },
  { id: 'demo-3', merchant: 'WinMart', amount: 326000, category: 'Mua sắm', date: '2026-10-23', note: 'Nhu yếu phẩm' },
  { id: 'demo-4', merchant: 'EVN', amount: 418000, category: 'Hóa đơn', date: '2026-10-21', note: 'Tiền điện tháng 10' },
  { id: 'demo-5', merchant: 'Pharmacity', amount: 135000, category: 'Sức khỏe', date: '2026-10-20', note: '' },
];

const storageKey = 'receiptly-demo-v1';
const pageTitles = { dashboard: 'Tổng quan', transactions: 'Sổ giao dịch', insights: 'Phân tích' };
const currency = new Intl.NumberFormat('vi-VN');
let transactions = loadTransactions();
let deferredInstallPrompt = null;

function loadTransactions() {
  try {
    const stored = localStorage.getItem(storageKey);
    return stored ? JSON.parse(stored) : structuredClone(sampleTransactions);
  } catch (_) {
    return structuredClone(sampleTransactions);
  }
}

function saveTransactions() {
  localStorage.setItem(storageKey, JSON.stringify(transactions));
}

function money(value) {
  return `${currency.format(Math.round(value))} ₫`;
}

function categoryMeta(name) {
  return categories.find((item) => item.name === name) || categories.at(-1);
}

function sortedTransactions() {
  return [...transactions].sort((a, b) => b.date.localeCompare(a.date) || b.id.localeCompare(a.id));
}

function escapeHtml(value) {
  const div = document.createElement('div');
  div.textContent = String(value ?? '');
  return div.innerHTML;
}

function transactionMarkup(transaction) {
  const meta = categoryMeta(transaction.category);
  const date = new Date(`${transaction.date}T00:00:00`);
  const shortDate = new Intl.DateTimeFormat('vi-VN', { day: '2-digit', month: '2-digit' }).format(date);
  return `
    <button class="transaction" data-edit="${escapeHtml(transaction.id)}">
      <i class="transaction-icon" style="background:${meta.color}22;color:${meta.color}">${meta.icon}</i>
      <span class="transaction-main"><b>${escapeHtml(transaction.merchant)}</b><small>${escapeHtml(transaction.category)} · ${shortDate}</small></span>
      <span class="transaction-amount">${money(transaction.amount)}</span>
    </button>`;
}

function emptyMarkup() {
  return '<div class="empty-state"><i>＋</i><b>Cuốn sổ đang trống</b><span>Quét hóa đơn hoặc ghi khoản chi đầu tiên để bắt đầu.</span></div>';
}

function render() {
  const sorted = sortedTransactions();
  const total = sorted.reduce((sum, item) => sum + Number(item.amount), 0);
  const totals = Object.fromEntries(categories.map((item) => [item.name, 0]));
  sorted.forEach((item) => { totals[item.category] = (totals[item.category] || 0) + Number(item.amount); });
  const top = Object.entries(totals).sort((a, b) => b[1] - a[1])[0];

  document.querySelector('#total-value').textContent = money(total);
  document.querySelector('#transaction-count').textContent = sorted.length;
  document.querySelector('#top-category').textContent = top?.[1] ? top[0] : '—';
  document.querySelector('#ledger-count').textContent = `${sorted.length} mục trong sổ`;
  document.querySelector('#ledger-total').textContent = money(total);
  document.querySelector('#chart-count').textContent = `${sorted.length} mục`;
  document.querySelector('#recent-list').innerHTML = sorted.length ? sorted.slice(0, 4).map(transactionMarkup).join('') : emptyMarkup();
  document.querySelector('#all-list').innerHTML = sorted.length ? sorted.map(transactionMarkup).join('') : emptyMarkup();

  renderDonut(totals, total);
  renderBars(sorted);
  bindTransactionButtons();
}

function renderDonut(totals, total) {
  let cursor = 0;
  const stops = [];
  categories.forEach((item) => {
    const next = total ? cursor + (totals[item.name] / total * 100) : cursor;
    if (next > cursor) stops.push(`${item.color} ${cursor.toFixed(2)}% ${next.toFixed(2)}%`);
    cursor = next;
  });
  document.querySelector('#donut').style.background = stops.length ? `conic-gradient(${stops.join(',')})` : 'conic-gradient(#e2ddd2 0 100%)';
  document.querySelector('#legend').innerHTML = categories.map((item) => {
    const percent = total ? Math.round(totals[item.name] / total * 100) : 0;
    return `<div class="legend-row"><i style="background:${item.color}"></i><span>${item.name}</span><small>${percent}%</small><b>${money(totals[item.name])}</b></div>`;
  }).join('');
}

function renderBars(sorted) {
  const days = Array.from({ length: 7 }, (_, index) => {
    const date = new Date('2026-10-25T00:00:00');
    date.setDate(date.getDate() - (6 - index));
    return date.toISOString().slice(0, 10);
  });
  const matrix = days.map((date) => categories.map((category) => sorted
    .filter((item) => item.date === date && item.category === category.name)
    .reduce((sum, item) => sum + Number(item.amount), 0)));
  const totals = matrix.map((day) => day.reduce((sum, value) => sum + value, 0));
  const max = Math.max(...totals, 1);
  document.querySelector('#bars').innerHTML = matrix.map((day, dayIndex) => {
    const height = Math.max(5, totals[dayIndex] / max * 110);
    const parts = day.map((value, index) => value > 0 ? `<span style="height:${value / Math.max(totals[dayIndex], 1) * height}px;background:${categories[index].color}"></span>` : '').join('');
    return `<div class="bar" style="height:${height}px">${parts || '<span style="height:5px;background:#cfc7dc"></span>'}</div>`;
  }).join('');
}

function goTo(page) {
  document.querySelectorAll('.app-page').forEach((element) => element.classList.toggle('active', element.dataset.page === page));
  document.querySelectorAll('.nav-item').forEach((element) => element.classList.toggle('active', element.dataset.go === page));
  document.querySelector('#page-title').textContent = pageTitles[page];
}

function openEntry(transaction = null) {
  const form = document.querySelector('#entry-form');
  form.reset();
  document.querySelector('#entry-id').value = transaction?.id || '';
  document.querySelector('#merchant').value = transaction?.merchant || '';
  document.querySelector('#amount').value = transaction?.amount || '';
  document.querySelector('#category').value = transaction?.category || 'Ăn uống';
  document.querySelector('#date').value = transaction?.date || '2026-10-25';
  document.querySelector('#note').value = transaction?.note || '';
  document.querySelector('#form-title').textContent = transaction ? 'Sửa giao dịch' : 'Ghi khoản chi';
  document.querySelector('#delete-entry').hidden = !transaction;
  document.querySelector('#entry-modal').showModal();
}

function bindTransactionButtons() {
  document.querySelectorAll('[data-edit]').forEach((button) => {
    button.addEventListener('click', () => openEntry(transactions.find((item) => item.id === button.dataset.edit)));
  });
}

function toast(message) {
  const element = document.querySelector('#toast');
  element.textContent = message;
  element.classList.add('show');
  window.setTimeout(() => element.classList.remove('show'), 2200);
}

document.addEventListener('click', (event) => {
  const go = event.target.closest('[data-go]');
  if (go) goTo(go.dataset.go);
  if (event.target.closest('[data-action="add"]')) openEntry();
});

document.querySelector('#entry-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const id = document.querySelector('#entry-id').value || `demo-${Date.now()}`;
  const record = {
    id,
    merchant: document.querySelector('#merchant').value.trim(),
    amount: Number(document.querySelector('#amount').value),
    category: document.querySelector('#category').value,
    date: document.querySelector('#date').value,
    note: document.querySelector('#note').value.trim(),
  };
  if (!record.merchant || !Number.isFinite(record.amount) || record.amount <= 0 || !record.date) {
    toast('Vui lòng nhập tên, số tiền và ngày hợp lệ.');
    return;
  }
  transactions = transactions.filter((item) => item.id !== id);
  transactions.push(record);
  saveTransactions();
  render();
  document.querySelector('#entry-modal').close();
  toast('Đã lưu giao dịch vào bản demo.');
});

document.querySelector('#delete-entry').addEventListener('click', () => {
  const id = document.querySelector('#entry-id').value;
  transactions = transactions.filter((item) => item.id !== id);
  saveTransactions();
  render();
  document.querySelector('#entry-modal').close();
  toast('Đã xóa giao dịch.');
});

document.querySelector('#reset-demo').addEventListener('click', () => {
  transactions = structuredClone(sampleTransactions);
  saveTransactions();
  render();
  toast('Đã đặt lại dữ liệu demo.');
});

const scanModal = document.querySelector('#scan-modal');
document.querySelector('#scan-button').addEventListener('click', () => scanModal.showModal());
document.querySelector('#close-scan').addEventListener('click', () => scanModal.close());
document.querySelector('#receipt-file').addEventListener('change', (event) => {
  if (!event.target.files?.length) return;
  const progress = document.querySelector('#scan-progress');
  progress.hidden = false;
  window.setTimeout(() => {
    progress.hidden = true;
    scanModal.close();
    openEntry({ id: '', merchant: 'Cửa hàng từ hóa đơn', amount: 128000, category: 'Ăn uống', date: '2026-10-25', note: 'Kết quả mô phỏng OCR — vui lòng kiểm tra' });
    document.querySelector('#form-title').textContent = 'Kiểm tra hóa đơn';
    document.querySelector('#entry-id').value = '';
    event.target.value = '';
  }, 1300);
});

window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  deferredInstallPrompt = event;
  document.querySelector('#install-app').hidden = false;
});

document.querySelector('#install-app').addEventListener('click', async () => {
  if (!deferredInstallPrompt) return;
  deferredInstallPrompt.prompt();
  await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  document.querySelector('#install-app').hidden = true;
});

window.addEventListener('appinstalled', () => toast('Receiptly demo đã được cài đặt.'));

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('./sw.js'));
}

render();
