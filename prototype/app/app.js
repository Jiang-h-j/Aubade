/* ===== Aubade 原型 · 交互逻辑 ===== */

const screen = document.getElementById('screen');
const tabbar = document.getElementById('tabbar');
const modalRoot = document.getElementById('modal-root');
const toastRoot = document.getElementById('toast-root');

let currentTab = 'add';   // 默认落地：记账页
let filter = { cat: 'all', range: 'month' };

/* ---------- 工具 ---------- */
function el(html) { const d = document.createElement('div'); d.innerHTML = html.trim(); return d.firstElementChild; }
function esc(s) { return (s ?? '').toString().replace(/[&<>"]/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;' }[c])); }

function toast(msg, warn) {
  const t = el(`<div class="toast ${warn ? 'warn' : ''}">${esc(msg)}</div>`);
  toastRoot.appendChild(t);
  setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 250); }, 2200);
}
function closeModal() { modalRoot.innerHTML = ''; }

/* ---------- iOS 风格顶部通知横幅（模拟后台入账推送） ---------- */
let notifSeq = 0;
function notifRootEl() {
  let r = document.getElementById('notif-root');
  if (!r) { r = el(`<div id="notif-root"></div>`); document.querySelector('.phone').appendChild(r); }
  return r;
}
function notifHTML(o) {
  const ico = { loading: '<span class="nf-spin"></span>', ok: '🌅', fail: '⚠️' }[o.kind] || '🌅';
  return `<div class="nf-ico ${o.kind}">${ico}</div>
    <div class="nf-main"><div class="nf-title">${esc(o.title)}</div><div class="nf-body">${o.body||''}</div></div>`;
}
function pushNotif(o) {
  const nid = 'nf' + (++notifSeq);
  const card = el(`<div class="notif" id="${nid}">${notifHTML(o)}</div>`);
  if (o.onTap) card.onclick = o.onTap;
  notifRootEl().appendChild(card);
  if (o.kind === 'ok' || o.kind === 'fail') scheduleNotifDismiss(nid);
  return nid;
}
function updateNotif(nid, o) {
  const card = document.getElementById(nid);
  if (!card) return pushNotif(o);
  card.className = 'notif';
  card.innerHTML = notifHTML(o);
  card.onclick = o.onTap || null;
  if (o.kind === 'ok' || o.kind === 'fail') scheduleNotifDismiss(nid);
}
function scheduleNotifDismiss(nid) {
  setTimeout(() => { const c = document.getElementById(nid); if (c) { c.style.opacity = '0'; c.style.transform = 'translateY(-12px)'; setTimeout(() => c.remove(), 300); } }, 4200);
}
function removeAllNotif() { const r = document.getElementById('notif-root'); if (r) r.innerHTML = ''; }

/* ---------- 顶层渲染 ---------- */
function render() {
  if (!State.onboarded) { renderOnboard(); tabbar.style.display = 'none'; return; }
  tabbar.style.display = 'flex';
  [...tabbar.children].forEach(b => b.classList.toggle('active', b.dataset.tab === currentTab));
  if (currentTab === 'bills') renderBills();
  else if (currentTab === 'add') renderAdd();
  else if (currentTab === 'stats') renderStats();
  else if (currentTab === 'mine') renderMine();
}

tabbar.addEventListener('click', e => {
  const btn = e.target.closest('.tab');
  if (!btn) return;
  currentTab = btn.dataset.tab;
  render();
});

/* ---------- 首次引导 ---------- */
function renderOnboard() {
  screen.innerHTML = '';
  const page = el(`
    <div class="onboard">
      <div class="logo">🌅</div>
      <h1>Aubade</h1>
      <div class="lead">私人记账，尽量不用你动手。<br>开始前，先记下你现在<b>所有账户加起来大约有多少钱</b>，作为剩余金额的起点。</div>
      <div class="field">
        <label>我的初始总额（元）</label>
        <input type="number" id="ob-init" placeholder="例如 12345" inputmode="decimal">
      </div>
      <button class="btn" id="ob-go">开始记账</button>
      <button class="btn ghost skip" id="ob-skip">先跳过，稍后在"我的"里设置</button>
    </div>
  `);
  page.querySelector('#ob-go').onclick = () => {
    const v = parseFloat(page.querySelector('#ob-init').value);
    State.initialBalance = isNaN(v) ? null : v;
    State.onboarded = true;
    currentTab = 'add';
    render();
    if (State.initialBalance != null) toast('已设置初始总额 ¥' + money(State.initialBalance));
  };
  page.querySelector('#ob-skip').onclick = () => { State.onboarded = true; currentTab = 'add'; render(); };
  screen.appendChild(page);
}

/* ---------- 账单（流水页） ---------- */
function renderBills() {
  screen.innerHTML = '';
  const rem = remaining();
  const page = el(`<div class="page"></div>`);

  page.appendChild(el(`
    <div class="hero">
      <div class="k">剩余总额</div>
      <div class="big tnum">${rem == null ? '—' : '¥' + money(rem)}</div>
      <div class="row">
        <div><div class="k2">本月支出</div><div class="v2 expense tnum">¥${money(monthExpense())}</div></div>
        <div><div class="k2">本月收入</div><div class="v2 income tnum">¥${money(monthIncome())}</div></div>
      </div>
    </div>
  `));

  const catName = filter.cat === 'all' ? '全部分类' : catLabel(filter.cat);
  const rangeName = { month: '本月', week: '本周', all: '全部时间' }[filter.range];
  const fb = el(`
    <div class="filter-bar">
      <div class="chip ${filter.cat!=='all'?'active':''}" id="f-cat">${esc(catName)} ▾</div>
      <div class="chip ${filter.range!=='month'?'active':''}" id="f-range">${esc(rangeName)} ▾</div>
      ${(filter.cat!=='all'||filter.range!=='month') ? '<div class="chip" id="f-clear">清除筛选</div>' : ''}
    </div>
  `);
  page.appendChild(fb);

  let list = State.bills.slice();
  if (filter.cat !== 'all') list = list.filter(b => b.cat === filter.cat);
  if (filter.range === 'week') list = list.filter(b => ['2026-07-10','2026-07-09','2026-07-08'].some(d=>b.time.startsWith(d)));

  if (list.length === 0) {
    page.appendChild(el(`<div class="empty"><span class="em-ico">🧾</span>${State.bills.length===0?'还没有账单<br>去「记账」记第一笔吧':'没有符合条件的账单<br>换个筛选试试'}</div>`));
  } else {
    const groups = {};
    list.sort((a,b)=> b.time.localeCompare(a.time));
    list.forEach(b => { const d = b.time.slice(0,10); (groups[d] = groups[d] || []).push(b); });
    Object.entries(groups).forEach(([day, items]) => {
      const g = el(`<div class="day-group"><div class="day-head">${fmtDay(day)}</div><div class="day-card"></div></div>`);
      const card = g.querySelector('.day-card');
      items.forEach(b => {
        const c = catColor(b.cat);
        const item = el(`
          <div class="bill-item" data-id="${b.id}">
            <div class="cat-badge" style="background:${hexA(c,.16)}">${catIcon(b.cat)}</div>
            <div class="bill-main">
              <div class="t1">${esc(b.merchant || b.note || catLabel(b.cat))}</div>
              <div class="t2">${esc(b.time.slice(11))} · ${srcName(b)}${b.dateUnknown?' · <span class="date-warn-inline">日期未识别</span>':''}${b.note && b.merchant ? ' · '+esc(b.note):''}</div>
            </div>
            <div class="bill-amt ${b.dir} tnum">${b.dir==='expense'?'-':'+'}${money(b.amount)}</div>
          </div>
        `);
        // 账单页：左滑删除（与记账页最近记录同款）
        card.appendChild(swipeRow(item, b.id));
      });
      page.appendChild(g);
    });
  }

  fb.querySelector('#f-cat').onclick = openCatFilter;
  fb.querySelector('#f-range').onclick = openRangeFilter;
  const clr = fb.querySelector('#f-clear'); if (clr) clr.onclick = () => { filter = {cat:'all',range:'month'}; render(); };
  screen.appendChild(page);
}

function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${(n>>16)&255},${(n>>8)&255},${n&255},${a})`;
}
function fmtDay(d) {
  const map = { '2026-07-10':'今天 · 7月10日', '2026-07-09':'昨天 · 7月9日' };
  return map[d] || d.replace(/2026-0?(\d+)-0?(\d+)/, '$1月$2日');
}
function srcName(b){
  const s = typeof b === 'string' ? b : b.source;
  const via = typeof b === 'object' ? b.via : null;
  if (s === 'screenshot' && via === 'shortcut') return '快捷指令';
  return {text:'文本',screenshot:'截图',voice:'语音',manual:'手动'}[s]||s;
}

function openCatFilter() {
  const opts = [{key:'all',label:'全部分类',icon:'🗂'}, ...CATS.expense, ...CATS.income];
  const sheet = buildSheet('选择分类', opts.map(o =>
    `<div class="list-row" data-k="${o.key}"><span>${o.icon||''} ${esc(o.label)}</span>${filter.cat===o.key?'<span class="badge-ok">✓</span>':''}</div>`).join(''));
  sheet.querySelectorAll('.list-row').forEach(r => r.onclick = () => { filter.cat = r.dataset.k; closeModal(); render(); });
}
function openRangeFilter() {
  const opts = [{k:'week',l:'本周'},{k:'month',l:'本月'},{k:'all',l:'全部时间'}];
  const sheet = buildSheet('时间范围', opts.map(o =>
    `<div class="list-row" data-k="${o.k}">${o.l}${filter.range===o.k?'<span class="badge-ok">✓</span>':''}</div>`).join(''));
  sheet.querySelectorAll('.list-row').forEach(r => r.onclick = () => { filter.range = r.dataset.k; closeModal(); render(); });
}

/* ---------- 记账 Tab ---------- */
function renderAdd() {
  screen.innerHTML = '';
  const rem = remaining();
  const todayCount = State.bills.filter(b => b.time.startsWith('2026-07-10')).length;
  const cardIco = (bg, ico) => `<div class="ico" style="background:${bg}">${ico}</div>`;
  const page = el(`
    <div class="page">
      <div class="add-hero">
        <div class="add-hero-txt"><h1>记一笔</h1><p>选一种方式，剩下的交给 Aubade</p></div>
        <div class="add-hero-chip">
          <div class="c-k">今日已记</div>
          <div class="c-v tnum">${todayCount}<span>笔</span></div>
        </div>
      </div>
      <div class="add-grid">
        <div class="add-card" data-m="screenshot">${cardIco('#fdeee9','📷')}<div class="lbl">截图识别</div><div class="sub">快捷指令随手截图</div></div>
        <div class="add-card" data-m="voice">${cardIco('#eef0fb','🎤')}<div class="lbl">语音记账</div><div class="sub">说一句话</div></div>
        <div class="add-card" data-m="text">${cardIco('#e9f5ee','📋')}<div class="lbl">文本识别</div><div class="sub">短信/账单文字</div></div>
        <div class="add-card" data-m="manual">${cardIco('#f5eefb','✏️')}<div class="lbl">手动输入</div><div class="sub">自己填</div></div>
      </div>
    </div>
  `);

  // 最近记录：用真实账单填充下半屏，形成“记完立刻看到”的闭环
  const recent = State.bills.slice().sort((a, b) => b.time.localeCompare(a.time)).slice(0, 4);
  const recentSec = el(`
    <div class="recent-sec">
      <div class="recent-head">
        <span class="recent-title">最近记录</span>
        ${State.bills.length ? '<span class="recent-more" id="see-all">全部 ›</span>' : ''}
      </div>
    </div>
  `);
  if (recent.length === 0) {
    recentSec.appendChild(el(`<div class="recent-empty"><span class="em-ico">🧾</span>记完的账单会出现在这里</div>`));
  } else {
    const card = el(`<div class="day-card"></div>`);
    recent.forEach(b => {
      const c = catColor(b.cat);
      const item = el(`
        <div class="bill-item" data-id="${b.id}">
          <div class="cat-badge" style="background:${hexA(c,.16)}">${catIcon(b.cat)}</div>
          <div class="bill-main">
            <div class="t1">${esc(b.merchant || b.note || catLabel(b.cat))}</div>
            <div class="t2">${esc(b.time.slice(5,16))} · ${srcName(b)}${b.dateUnknown?' · <span class="date-warn-inline">日期未识别</span>':''}</div>
          </div>
          <div class="bill-amt ${b.dir} tnum">${b.dir==='expense'?'-':'+'}${money(b.amount)}</div>
        </div>
      `);
      // R3：最近记录支持左滑删除（复用账单页同款 swipeRow）
      card.appendChild(swipeRow(item, b.id));
    });
    recentSec.appendChild(card);
  }
  page.appendChild(recentSec);

  page.querySelectorAll('.add-card').forEach(c => c.onclick = () => startEntry(c.dataset.m));
  const seeAll = recentSec.querySelector('#see-all');
  if (seeAll) seeAll.onclick = () => { currentTab = 'bills'; render(); };
  const swipeHint = recent.length ? el(`<div class="swipe-hint">← 左滑一条可删除</div>`) : null;
  if (swipeHint) recentSec.appendChild(swipeHint);
  screen.appendChild(page);
}

function startEntry(mode) {
  if (mode === 'manual') return openManualForm();
  if (mode === 'text') return openTextInput();
  if (mode === 'screenshot') return openScreenshotSheet();
  if (needKeyBlocked()) return;
  if (mode === 'voice') openVoiceCapture();
}

/* ---- 截图识别：说明快捷指令主入口 + 相册选图备选 ---- */
function openScreenshotSheet() {
  const sheet = buildSheet('截图识别', `
    <div class="ss-intro">
      <div class="ss-hero">📷➜🌅</div>
      <div class="ss-desc">主用法：在支付宝/微信/银行的付款结果页，用 <b>iOS 快捷指令</b> 随手一截，图片会自动发给 Aubade，<b>后台识别并直接入账</b>，只弹一条通知告诉你结果——不用切来切去。</div>
    </div>
    <div class="ss-steps">
      <div class="ss-step"><span class="n">1</span>去「快捷指令」App 新建：截屏 → 发送给 Aubade</div>
      <div class="ss-step"><span class="n">2</span>之后付完款触发它（背面轻点 / 分享菜单 / 语音）即可</div>
    </div>
    <button class="btn secondary" id="ss-demo">▶︎ 演示：模拟收到一张快捷指令截图</button>
    <div class="ss-or"><span>或</span></div>
    <button class="btn" id="ss-album">🖼 从相册选一张图识别</button>
    <button class="btn ghost" id="ss-multi" style="margin-top:8px">🧾 演示：选一张含多笔的账单截图</button>
  `);
  sheet.querySelector('#ss-demo').onclick = () => { closeModal(); if (needKeyBlocked()) return; runShortcutIntake(); };
  sheet.querySelector('#ss-album').onclick = () => { closeModal(); if (needKeyBlocked()) return; recognizeFlow('screenshot', '正在识别截图…', '本地读取文字 → DeepSeek 解析'); };
  sheet.querySelector('#ss-multi').onclick = () => { closeModal(); if (needKeyBlocked()) return; _forceMultiOnce = true; recognizeFlow('screenshot', '正在识别账单截图…', '本地读取文字 → DeepSeek 解析多笔'); };
}

// 让"演示多笔"入口临时把本次截图识别走多笔流（不改全局开关）
let _forceMultiOnce = false;

/* 模拟"快捷指令截图 → 后台入账 → 通知"：不切页面，只在顶部弹通知条 */
function runShortcutIntake() {
  const nId = pushNotif({ kind: 'loading', title: '收到快捷指令截图', body: '后台识别中…（本地读字 → DeepSeek）' });
  setTimeout(() => {
    if (State.simFail) {
      updateNotif(nId, { kind: 'fail', title: '这张截图没识别出金额', body: '点此打开 Aubade 手动补录（原图已保留）', onTap: () => { removeAllNotif(); openManualForm({ note: MOCK_SHORTCUT_SHOT.raw.replace(/^\[[^\]]+\]\n?/, '') }); } });
      return;
    }
    const r = MOCK_SHORTCUT_SHOT;
    const bill = { id: id(), amount: r.amount, dir: r.dir, cat: r.cat, time: r.time, merchant: r.merchant, note: r.note, source: 'screenshot', via: 'shortcut', raw: r.raw };
    State.bills.push(bill);
    if (currentTab === 'add' || currentTab === 'bills') render();
    updateNotif(nId, { kind: 'ok', title: '已记一笔 · 支出 ¥' + money(r.amount), body: `${catIcon(r.cat)} ${catLabel(r.cat)} · ${esc(r.merchant)} · 点此查看/修改`, onTap: () => { removeAllNotif(); currentTab = 'bills'; render(); openResultCard(bill.id, true); } });
  }, 1600);
}

function needKeyBlocked() {
  if (State.simNoKey || !State.keyConfigured) {
    confirmDialog('需要先配置 DeepSeek', '识别类记账要用到 DeepSeek。请先在「我的 → DeepSeek API Key」里填写。手动记账不受影响。',
      '去配置', () => { closeModal(); currentTab = 'mine'; render(); }, '取消');
    return true;
  }
  return false;
}

function openVoiceCapture() {
  const sheet = buildSheet('语音记账', `
    <div style="text-align:center;padding:10px 0 4px">
      <div style="font-size:46px">🎤</div>
      <div style="margin:16px 0;color:var(--ink-2);font-size:14px">按住下面按钮说话（演示：点一下即可）</div>
      <button class="btn" id="v-say">按住说话 / 点此模拟</button>
      <div style="font-size:12px;color:var(--ink-3);margin-top:12px">示例：「打车花了 20 块」</div>
    </div>
  `);
  sheet.querySelector('#v-say').onclick = () => { closeModal(); recognizeFlow('voice', '正在识别语音…', '本地转文字 → DeepSeek 解析'); };
}

/* ---- 文本识别（原"粘贴短信"，泛化为任意含金额文本） ---- */
function openTextInput() {
  screen.innerHTML = '';
  const page = el(`
    <div class="page">
      <div class="sub-header"><span class="back">‹</span><span class="title">文本识别</span></div>
      <div class="form">
        <div class="field">
          <label>粘贴任意含金额的文字（银行短信、支付结果、聊天记录都行）</label>
          <textarea id="txt-input" placeholder="例如：\n【工商银行】您尾号1234的储蓄卡…支出人民币256.00元，商户京东商城\n或：昨天在楼下超市买菜花了 128"></textarea>
        </div>
        <button class="btn secondary" id="txt-clip">📋 读取剪贴板（演示：填入示例文本）</button>
        <div style="height:12px"></div>
        <button class="btn" id="txt-go">识别并记账</button>
      </div>
    </div>
  `);
  page.querySelector('.back').onclick = () => { currentTab='add'; render(); };
  page.querySelector('#txt-clip').onclick = () => { page.querySelector('#txt-input').value = SAMPLE_TEXT; toast('已读取剪贴板'); };
  page.querySelector('#txt-go').onclick = () => {
    const txt = page.querySelector('#txt-input').value.trim();
    if (!txt) return toast('请先粘贴或输入文字', true);
    if (needKeyBlocked()) return;
    recognizeFlow('text', '正在识别文本…', 'DeepSeek 提取金额与分类');
  };
  screen.appendChild(page);
}

function recognizeFlow(mode, title, sub) {
  screen.innerHTML = '';
  screen.appendChild(el(`
    <div class="page"><div class="recog">
      <div class="spinner"></div>
      <div class="t">${esc(title)}</div>
      <div class="s">${esc(sub)}</div>
    </div></div>
  `));
  setTimeout(() => {
    if (State.simFail) return recognizeFailed(mode);
    // R5：截图入口且（开启"多笔"演示 或 本次由多笔入口触发）→ 走多笔结果流
    if (mode === 'screenshot' && (State.simMulti || _forceMultiOnce)) { _forceMultiOnce = false; return recognizeMulti(); }
    const r = MOCK_RECOGNIZE[mode];
    // R2：开启"识别不到日期"演示时，兜底到今天并标记 dateUnknown，让结果卡片高亮提示
    const noDate = State.simNoDate;
    const time = noDate ? (TODAY + ' 00:00') : r.time;
    const bill = { id: id(), amount: r.amount, dir: r.dir, cat: r.cat, time, merchant: r.merchant, note: r.note, source: mode, raw: r.raw, dateUnknown: noDate };
    State.bills.push(bill);
    currentTab = 'bills';
    render();
    openResultCard(bill.id, true);
  }, 1400);
}

function recognizeFailed(mode) {
  const raw = MOCK_RECOGNIZE[mode].raw;
  confirmDialog('没能识别出金额', '这段内容没能解析出有效金额。原始文本已保留，可以转为手动填写。',
    '转手动填写', () => { closeModal(); openManualForm({ note: raw.replace(/^\[[^\]]+\]\n?/, '') }); }, '取消',
    () => { currentTab='add'; render(); });
}

/* ---- R5 截图多笔：一张截图识别出多笔，逐条确认入账 ---- */
function recognizeMulti() {
  // 把 mock 多笔落成正式账单（识别即入账，与单笔一致），再弹多笔结果卡逐条确认/改/删
  const raw = MOCK_MULTI_SHOT.raw;
  const ids = MOCK_MULTI_SHOT.items.map(it => {
    const b = { id: id(), amount: it.amount, dir: it.dir, cat: it.cat, time: it.time, merchant: it.merchant, note: it.note, source: 'screenshot', raw, dateUnknown: it.dateUnknown };
    State.bills.push(b);
    return b.id;
  });
  currentTab = 'bills';
  render();
  openMultiResultCard(ids);
}

function openMultiResultCard(billIds) {
  let ids = billIds.slice();
  const overlay = el(`<div class="overlay"></div>`);
  const sheet = el(`<div class="sheet"><div class="grab"></div></div>`);
  overlay.appendChild(sheet); modalRoot.appendChild(overlay);
  overlay.onclick = e => { if (e.target === overlay) closeModal(); };

  const draw = () => {
    const bills = ids.map(i => State.bills.find(b => b.id === i)).filter(Boolean);
    const total = bills.filter(b=>b.dir==='expense').reduce((s,b)=>s+b.amount,0);
    sheet.innerHTML = `<div class="grab"></div>
      <div class="sheet-head"><span class="ok">✓</span> 已识别 ${bills.length} 笔</div>
      <div class="multi-sum">这张截图识别出 ${bills.length} 笔，已全部入账。逐条看一眼，可单独改 / 删。<span class="tnum">支出合计 ¥${money(total)}</span></div>
      <div class="multi-list">
        ${bills.map(b => `
          <div class="multi-item" data-id="${b.id}">
            <div class="cat-badge" style="background:${hexA(catColor(b.cat),.16)}">${catIcon(b.cat)}</div>
            <div class="bill-main">
              <div class="t1">${esc(b.merchant || catLabel(b.cat))}</div>
              <div class="t2">${esc(b.time.slice(5,16))}${b.dateUnknown?' · <span class="date-warn-inline">日期未识别</span>':''}</div>
            </div>
            <div class="bill-amt ${b.dir} tnum">${b.dir==='expense'?'-':'+'}${money(b.amount)}</div>
            <button class="multi-del" data-del="${b.id}" title="删除这笔">✕</button>
          </div>`).join('')}
      </div>
      <div class="raw-fold" id="m-raw">▸ 查看识别到的原始文本<div class="body">${esc(MOCK_MULTI_SHOT.raw)}</div></div>
      <button class="btn" id="m-done">完成（${bills.length} 笔已记）</button>`;

    // 点某笔 → 单笔结果卡编辑（改完回来刷新列表）
    sheet.querySelectorAll('.multi-item').forEach(row => row.onclick = e => {
      if (e.target.closest('.multi-del')) return;
      closeModal(); openResultCard(row.dataset.id, false);
    });
    // 单笔删除（二次确认），删到 0 笔自动关闭
    sheet.querySelectorAll('.multi-del').forEach(btn => btn.onclick = () => {
      const bid = btn.dataset.del;
      confirmDialog('删除这笔？', '仅删除这一笔，其余识别结果保留。', '删除', () => {
        State.bills = State.bills.filter(x => x.id !== bid);
        ids = ids.filter(x => x !== bid);
        closeModal(); render();
        if (ids.length === 0) { toast('已删除'); return; }
        openMultiResultCard(ids); toast('已删除这笔');
      }, '取消', null, true);
    });
    const rawFold = sheet.querySelector('#m-raw'); if (rawFold) rawFold.onclick = () => rawFold.classList.toggle('open');
    sheet.querySelector('#m-done').onclick = () => { closeModal(); render(); toast(`已记 ${bills.length} 笔`); };
  };
  draw();
}

/* ---- 结果卡片（识别后已入账，可当场改） ---- */
function openResultCard(billId, justAdded) {
  const b = State.bills.find(x => x.id === billId);
  if (!b) return;
  const catOpts = (dir) => CATS[dir].map(c => `<option value="${c.key}" ${b.cat===c.key?'selected':''}>${c.icon} ${c.label}</option>`).join('');
  const overlay = el(`<div class="overlay"></div>`);
  const sheet = el(`
    <div class="sheet">
      <div class="grab"></div>
      <div class="sheet-head">${justAdded?'<span class="ok">✓</span>':''} ${justAdded ? '已记一笔' : '账单详情'}</div>
      <div class="field"><label>金额（元）</label><input type="number" id="r-amt" value="${b.amount}"></div>
      <div class="field"><label>方向</label>
        <div class="seg" id="r-dir">
          <button data-d="expense" class="${b.dir==='expense'?'on':''}">支出</button>
          <button data-d="income" class="${b.dir==='income'?'on':''}">收入</button>
        </div>
      </div>
      <div class="field"><label>分类</label><select id="r-cat">${catOpts(b.dir)}</select></div>
      <div class="field">
        <label>时间${b.dateUnknown ? ' <span class="date-warn-tag">日期未识别</span>' : ''}</label>
        <input type="text" id="r-time" value="${esc(b.time)}">
        ${b.dateUnknown ? '<div class="field-hint warn">没从截图/文本里读到消费日期，已先按今天填，请确认或改成真实日期。</div>' : ''}
      </div>
      <div class="field"><label>商户 / 对方</label><input type="text" id="r-mer" value="${esc(b.merchant)}"></div>
      <div class="field"><label>备注</label><input type="text" id="r-note" value="${esc(b.note)}"></div>
      ${b.raw ? `<div class="raw-fold" id="r-raw">▸ 查看识别到的原始文本<div class="body">${esc(b.raw)}</div></div>` : ''}
      <div class="result-btns">
        <button class="btn secondary" id="r-del" style="flex:1">删除</button>
        <button class="btn" id="r-done" style="flex:2">完成</button>
      </div>
    </div>
  `);
  overlay.appendChild(sheet);
  modalRoot.appendChild(overlay);

  sheet.querySelectorAll('#r-dir button').forEach(btn => btn.onclick = () => {
    b.dir = btn.dataset.d;
    sheet.querySelectorAll('#r-dir button').forEach(x=>x.classList.toggle('on', x.dataset.d===b.dir));
    b.cat = CATS[b.dir][0].key;
    sheet.querySelector('#r-cat').innerHTML = catOpts(b.dir);
  });
  const rawFold = sheet.querySelector('#r-raw'); if (rawFold) rawFold.onclick = () => rawFold.classList.toggle('open');

  sheet.querySelector('#r-done').onclick = () => {
    b.amount = parseFloat(sheet.querySelector('#r-amt').value) || b.amount;
    b.cat = sheet.querySelector('#r-cat').value;
    const newTime = sheet.querySelector('#r-time').value;
    if (b.dateUnknown && newTime !== b.time) b.dateUnknown = false; // 用户已确认/改过日期
    b.time = newTime;
    b.merchant = sheet.querySelector('#r-mer').value;
    b.note = sheet.querySelector('#r-note').value;
    closeModal(); render(); toast('已保存');
  };
  sheet.querySelector('#r-del').onclick = () => {
    confirmDialog('删除这笔账单？', '删除后无法恢复。', '删除', () => {
      State.bills = State.bills.filter(x => x.id !== b.id);
      closeModal(); render(); toast('已删除');
    }, '取消', null, true);
  };
}
function openBillEdit(billId) { openResultCard(billId, false); }

/* ---- 侧滑删除包装（R3：记账页最近记录 / 账单页复用同款交互）----
   把一个 bill-item 包进可左滑的容器：左滑露出「删除」→ 点删除走二次确认；
   未滑动时点内容进编辑，已露出时点内容先收起。鼠标拖拽也可触发，贴近真机 swipeActions。 */
const DEL_W = 76;
function swipeRow(itemEl, billId, onAfterDelete) {
  const wrap = el(`
    <div class="swipe">
      <div class="swipe-action"><button class="swipe-del">删除</button></div>
      <div class="swipe-content"></div>
    </div>
  `);
  const content = wrap.querySelector('.swipe-content');
  content.appendChild(itemEl);

  let open = false, startX = 0, dx = 0, dragging = false, moved = false;
  const setX = x => { content.style.transform = `translateX(${x}px)`; };
  const setOpen = v => { open = v; content.style.transition = 'transform .2s'; setX(v ? -DEL_W : 0); };

  content.addEventListener('pointerdown', e => {
    dragging = true; moved = false; startX = e.clientX; dx = 0;
    content.style.transition = 'none';
    content.setPointerCapture(e.pointerId);
  });
  content.addEventListener('pointermove', e => {
    if (!dragging) return;
    dx = e.clientX - startX;
    if (Math.abs(dx) > 4) moved = true;
    let base = open ? -DEL_W : 0;
    let x = Math.min(0, Math.max(-DEL_W, base + dx)); // 只允许左滑，夹在 [-DEL_W,0]
    setX(x);
  });
  content.addEventListener('pointerup', () => {
    if (!dragging) return;
    dragging = false;
    setOpen((open ? -DEL_W : 0) + dx < -DEL_W / 2); // 滑过一半吸附露出
  });

  itemEl.addEventListener('click', e => {
    if (moved) { e.preventDefault(); e.stopPropagation(); return; } // 拖拽结束的 click 不算点击
    if (open) { setOpen(false); return; }
    openBillEdit(billId);
  }, true);

  wrap.querySelector('.swipe-del').onclick = () => {
    confirmDialog('删除这笔账单？', '删除后无法恢复，剩余总额与统计会同步更新。', '删除', () => {
      State.bills = State.bills.filter(x => x.id !== billId);
      closeModal(); render(); toast('已删除');
      if (onAfterDelete) onAfterDelete();
    }, '取消', null, true);
  };
  return wrap;
}

/* ---- 手动表单 ---- */
function openManualForm(prefill = {}) {
  screen.innerHTML = '';
  let dir = prefill.dir || 'expense';
  const page = el(`
    <div class="page">
      <div class="sub-header"><span class="back">‹</span><span class="title">手动记账</span></div>
      <div class="form">
        <div class="field"><label>金额（元）</label><input type="number" id="m-amt" placeholder="0.00" value="${prefill.amount||''}"></div>
        <div class="field"><label>方向</label>
          <div class="seg" id="m-dir"><button data-d="expense" class="on">支出</button><button data-d="income">收入</button></div>
        </div>
        <div class="field"><label>分类</label><select id="m-cat"></select></div>
        <div class="field"><label>日期</label><input type="text" id="m-time" value="2026-07-10 12:00"></div>
        <div class="field"><label>备注</label><input type="text" id="m-note" value="${esc(prefill.note||'')}"></div>
        <button class="btn" id="m-save">保存</button>
      </div>
    </div>
  `);
  const catSel = page.querySelector('#m-cat');
  const fillCats = () => { catSel.innerHTML = CATS[dir].map(c=>`<option value="${c.key}">${c.icon} ${c.label}</option>`).join(''); };
  fillCats();
  page.querySelectorAll('#m-dir button').forEach(btn => btn.onclick = () => {
    dir = btn.dataset.d;
    page.querySelectorAll('#m-dir button').forEach(x=>x.classList.toggle('on', x.dataset.d===dir));
    fillCats();
  });
  page.querySelector('.back').onclick = () => { currentTab='add'; render(); };
  page.querySelector('#m-save').onclick = () => {
    const amt = parseFloat(page.querySelector('#m-amt').value);
    if (!amt || amt <= 0) return toast('请输入有效金额', true);
    State.bills.push({ id: id(), amount: amt, dir, cat: catSel.value, time: page.querySelector('#m-time').value, merchant: '', note: page.querySelector('#m-note').value, source: 'manual' });
    currentTab = 'bills'; render(); toast('已记一笔');
  };
  screen.appendChild(page);
}

/* ---------- 统计 ---------- */
let statGrain = 'month';   // day | week | month | year
let statOffset = 0;        // 相对今天的偏移（0=当前，-1=上一个）
function renderStats() {
  screen.innerHTML = '';
  const range = periodRange(statGrain, statOffset);
  const bills = billsInRange(range.start, range.end);
  const exp = rangeSum(bills, 'expense');
  const inc = rangeSum(bills, 'income');
  const page = el(`<div class="page stats-page"></div>`);

  // 粒度切换
  const GRAINS = [['day','日'],['week','周'],['month','月'],['year','年']];
  page.appendChild(el(`
    <div class="grain-seg" id="s-grain">
      ${GRAINS.map(([k,l])=>`<button data-g="${k}" class="${statGrain===k?'on':''}">${l}</button>`).join('')}
    </div>
  `));

  // 时间导航条：‹ 标题 ›（不能翻到未来）
  const atNow = statOffset >= 0;
  const nav = el(`
    <div class="time-nav">
      <button class="nav-arrow" id="nav-prev" aria-label="上一个">‹</button>
      <div class="nav-label"><span class="nav-title">${range.title}</span>${range.sub?`<span class="nav-sub">${range.sub}</span>`:''}</div>
      <button class="nav-arrow ${atNow?'disabled':''}" id="nav-next" aria-label="下一个" ${atNow?'disabled':''}>›</button>
    </div>
  `);
  page.appendChild(nav);

  // 总支出 / 总收入
  page.appendChild(el(`
    <div class="stat-cards">
      <div class="stat-card"><div class="k">${statGrain==='day'?'当天支出':'总支出'}</div><div class="v expense tnum">¥${money(exp)}</div></div>
      <div class="stat-card"><div class="k">${statGrain==='day'?'当天收入':'总收入'}</div><div class="v income tnum">¥${money(inc)}</div></div>
    </div>
  `));

  if (statGrain === 'day') {
    // 日档：直接列当天每一笔流水
    renderDayBills(page, bills);
  } else {
    // 周/月/年档：趋势 + 分类占比 + 预算
    const trend = trendSeries(statGrain, statOffset);
    const tmax = Math.max(...trend.values, 0);
    const nonZero = trend.values.filter(v=>v>0);
    const avg = nonZero.length ? Math.round(trend.values.reduce((a,b)=>a+b,0)/trend.values.length) : 0;
    const trendTitle = { week:'支出趋势（本周每日）', month:'支出趋势（当月每日）', year:'支出趋势（当年每月）' }[statGrain];
    const panel = el(`
      <div class="panel">
        <div class="panel-head"><div class="panel-title">${trendTitle}</div></div>
        <div class="chart-wrap">${exp>0 ? lineChart(trend) : '<div class="chart-empty">本期还没有支出</div>'}</div>
        ${exp>0 ? `<div class="chart-peak">峰值 ¥${money(tmax)} · 均值 ¥${money(avg)}</div>` : ''}
      </div>
    `);
    page.appendChild(panel);

    const rows = rangeCatBreakdown(bills, 'expense');
    page.appendChild(el(`<div class="sec-title">支出分类占比</div>`));
    if (rows.length === 0) page.appendChild(el(`<div class="empty">本期还没有支出</div>`));
    rows.forEach(r => {
      const row = el(`
        <div class="bar-row tappable" data-cat="${esc(r.cat)}">
          <div class="lab"><span class="name">${catIcon(r.cat)} ${esc(catLabel(r.cat))}</span><span class="val">${r.pct}% · ¥${money(r.val)} ›</span></div>
          <div class="bar-track"><div class="bar-fill" style="width:${r.pct}%;background:${catColor(r.cat)}"></div></div>
        </div>
      `);
      row.onclick = () => openCatDetail(r.cat, range);
      page.appendChild(row);
    });

    // 预算：仅周/月档显示（年档无预算概念）
    if (statGrain === 'week' || statGrain === 'month') {
      const budget = statGrain === 'month' ? State.budgets.month : State.budgets.week;
      const label = statGrain === 'month' ? '月' : '周';
      page.appendChild(el(`<div class="sec-title">${label}预算</div>`));
      if (!budget) {
        const be = el(`<div class="budget-empty">还没设置${label}预算，去「我的」设置 ›</div>`);
        be.onclick = () => { currentTab='mine'; render(); };
        page.appendChild(be);
      } else {
        const pct = Math.round(exp / budget * 100);
        const over = pct > 100;
        page.appendChild(el(`
          <div class="budget-box ${over?'over':''}">
            <div class="bhead"><span>预算 ¥${money(budget)}</span><span class="pct tnum">${pct}%${over?' 已超支！':''}</span></div>
            <div class="bar-track big"><div class="bar-fill ${over?'over':''}" style="width:${Math.min(pct,100)}%;background:var(--brand)"></div></div>
            <div style="font-size:12px;color:var(--ink-3);margin-top:9px">已用 ¥${money(exp)} · 剩余 ¥${money(Math.max(budget-exp,0))}</div>
          </div>
        `));
      }
    }
  }

  // 交互绑定
  page.querySelectorAll('#s-grain button').forEach(btn => btn.onclick = () => { statGrain = btn.dataset.g; statOffset = 0; render(); });
  nav.querySelector('#nav-prev').onclick = () => { statOffset -= 1; render(); };
  const nx = nav.querySelector('#nav-next'); if (nx && !atNow) nx.onclick = () => { statOffset += 1; render(); };
  screen.appendChild(page);
}

// 日档：列出当天每一笔账单，点进可编辑；空态引导
function renderDayBills(page, bills) {
  if (bills.length === 0) {
    page.appendChild(el(`<div class="empty"><span class="em-ico">🗓</span>这一天还没有账单</div>`));
    return;
  }
  const sorted = bills.slice().sort((a,b)=> b.time.localeCompare(a.time));
  const g = el(`<div class="day-group" style="margin-top:14px"><div class="day-card"></div></div>`);
  const card = g.querySelector('.day-card');
  sorted.forEach(b => {
    const c = catColor(b.cat);
    const item = el(`
      <div class="bill-item" data-id="${b.id}">
        <div class="cat-badge" style="background:${hexA(c,.16)}">${catIcon(b.cat)}</div>
        <div class="bill-main">
          <div class="t1">${esc(b.merchant || b.note || catLabel(b.cat))}</div>
          <div class="t2">${esc(b.time.slice(11))} · ${srcName(b)}${b.note && b.merchant ? ' · '+esc(b.note):''}</div>
        </div>
        <div class="bill-amt ${b.dir} tnum">${b.dir==='expense'?'-':'+'}${money(b.amount)}</div>
      </div>
    `);
    item.onclick = () => openBillEdit(b.id);
    card.appendChild(item);
  });
  page.appendChild(g);
}

// 分类明细弹窗：列出当前时间区间内该分类的全部记录，点进可编辑
function openCatDetail(cat, range) {
  const list = billsInRange(range.start, range.end)
    .filter(b => b.dir === 'expense' && b.cat === cat)
    .sort((a, b) => b.time.localeCompare(a.time));
  const sum = list.reduce((s, b) => s + b.amount, 0);
  const title = `${catIcon(cat)} ${catLabel(cat)} · ${range.title}`;
  const body = `
    <div class="cat-detail-sum"><span>共 ${list.length} 笔</span><span class="tnum">合计 ¥${money(sum)}</span></div>
    <div class="cat-detail-list">
      ${list.map(b => `
        <div class="bill-item cd-item" data-id="${b.id}">
          <div class="cat-badge" style="background:${hexA(catColor(b.cat),.16)}">${catIcon(b.cat)}</div>
          <div class="bill-main">
            <div class="t1">${esc(b.merchant || b.note || catLabel(b.cat))}</div>
            <div class="t2">${esc(b.time.slice(5,16))} · ${srcName(b)}${b.note && b.merchant ? ' · '+esc(b.note):''}</div>
          </div>
          <div class="bill-amt expense tnum">-${money(b.amount)}</div>
        </div>
      `).join('')}
    </div>
  `;
  const sheet = buildSheet(title, body);
  sheet.querySelectorAll('.cd-item').forEach(item => {
    item.onclick = () => { closeModal(); openBillEdit(item.dataset.id); };
  });
}

/* SVG 折线图（带面积渐变、数据点、峰值高亮） */
function lineChart(trend) {
  const W = 322, H = 130, padX = 10, padY = 16;
  const vals = trend.values, labels = trend.labels;
  const max = Math.max(...vals, 1), min = 0;
  const n = vals.length;
  const stepX = (W - padX*2) / (n - 1);
  const y = v => H - padY - (v - min) / (max - min) * (H - padY*2 - 6);
  const x = i => padX + i * stepX;
  const pts = vals.map((v,i) => [x(i), y(v)]);
  const linePath = pts.map((p,i) => (i? 'L':'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  const areaPath = `${linePath} L ${x(n-1).toFixed(1)} ${H-padY} L ${padX} ${H-padY} Z`;
  const peakI = vals.indexOf(max);
  const dots = pts.map((p,i) => {
    const isPeak = i===peakI;
    return `<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="${isPeak?4.5:3}" fill="${isPeak?'#5b6ee1':'#fff'}" stroke="#5b6ee1" stroke-width="2"/>`;
  }).join('');
  const peakLabel = `<text x="${x(peakI).toFixed(1)}" y="${(y(max)-10).toFixed(1)}" text-anchor="middle" font-size="10" fill="#5b6ee1" font-weight="700">¥${Math.round(max)}</text>`;
  const xlabels = labels.map((l,i) => `<text x="${x(i).toFixed(1)}" y="${H-2}" text-anchor="middle" font-size="9.5" fill="#a3a8b3">${l}</text>`).join('');
  return `
    <svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}" preserveAspectRatio="xMidYMid meet">
      <defs>
        <linearGradient id="area" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#5b6ee1" stop-opacity="0.22"/>
          <stop offset="100%" stop-color="#5b6ee1" stop-opacity="0"/>
        </linearGradient>
      </defs>
      <path d="${areaPath}" fill="url(#area)"/>
      <path d="${linePath}" fill="none" stroke="#5b6ee1" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
      ${dots}${peakLabel}${xlabels}
    </svg>`;
}

/* ---------- 我的 ---------- */
function renderMine() {
  screen.innerHTML = '';
  const rem = remaining();
  const page = el(`<div class="page"></div>`);
  page.appendChild(el(`
    <div class="mine-hero">
      <div class="k">剩余总额（所有账户合计）</div>
      <div class="v ${rem==null?'unset':''} tnum">${rem==null?'未设置':'¥'+money(rem)}</div>
      <button class="btn" id="edit-init">${rem==null?'录入初始总额':'调整初始总额'}</button>
    </div>
  `));

  page.appendChild(el(`<div class="group-label">预算设置</div>`));
  const bg = el(`
    <div class="list-card">
      <div class="list-row"><span>周预算</span><input type="number" id="bw" value="${State.budgets.week||''}" placeholder="未设置"></div>
      <div class="list-row"><span>月预算</span><input type="number" id="bm" value="${State.budgets.month||''}" placeholder="未设置"></div>
    </div>
  `);
  page.appendChild(bg);

  page.appendChild(el(`<div class="group-label">智能识别</div>`));
  const keyCard = el(`
    <div class="list-card">
      <div class="list-row" id="key-row"><span>DeepSeek API Key</span>
        <span class="r">${State.keyConfigured && !State.simNoKey ? '<span class="badge-ok">已配置 ✓</span>' : '<span class="badge-no">去填写 ›</span>'}</span>
      </div>
    </div>
  `);
  page.appendChild(keyCard);

  page.appendChild(el(`<div class="group-label">分类管理</div>`));
  const catCard = el(`<div class="list-card cat-manage"></div>`);
  const renderCatManage = () => {
    const rowHTML = (c, dir) => `
      <div class="cat-mrow" data-dir="${dir}" data-key="${esc(c.key)}">
        <span class="cat-badge sm" style="background:${hexA(c.color,.16)}">${c.icon}</span>
        <span class="cat-mname">${esc(c.label)}</span>
        ${c.isPreset
          ? '<span class="cat-lock">预置 · 锁定</span>'
          : '<span class="cat-edit">编辑 ›</span>'}
      </div>`;
    catCard.innerHTML = `
      <div class="cat-mgroup-h">支出分类</div>
      ${CATS.expense.map(c => rowHTML(c,'expense')).join('')}
      <div class="cat-mgroup-h">收入分类</div>
      ${CATS.income.map(c => rowHTML(c,'income')).join('')}
      <div class="cat-mrow cat-add" id="cat-add">＋ 新增自定义分类</div>`;
    catCard.querySelectorAll('.cat-mrow[data-key]').forEach(row => {
      const dir = row.dataset.dir, key = row.dataset.key;
      const c = CATS[dir].find(x => x.key === key);
      row.onclick = () => {
        if (c.isPreset) return toast('预置分类不可修改');
        openCatEditor(dir, c, renderCatManage);
      };
    });
    catCard.querySelector('#cat-add').onclick = () => openCatEditor(null, null, renderCatManage);
  };
  renderCatManage();
  page.appendChild(catCard);

  page.querySelector('#edit-init').onclick = openInitEdit;
  bg.querySelector('#bw').onchange = e => { State.budgets.week = parseFloat(e.target.value)||0; toast('周预算已更新'); };
  bg.querySelector('#bm').onchange = e => { State.budgets.month = parseFloat(e.target.value)||0; toast('月预算已更新'); };
  keyCard.querySelector('#key-row').onclick = openKeyEdit;
  screen.appendChild(page);
}

function openInitEdit() {
  const sheet = buildSheet('设置初始总额', `
    <div class="grab" style="margin-top:-8px"></div>
    <div class="field"><label>你现在所有账户加起来大约有多少钱（元）</label>
      <input type="number" id="init-in" value="${State.initialBalance ?? ''}" placeholder="例如 12345"></div>
    <div style="font-size:12px;color:var(--ink-3);margin-bottom:16px">之后每记一笔收支，剩余总额会自动加减。</div>
    <button class="btn" id="init-save">保存</button>
  `);
  sheet.querySelector('#init-save').onclick = () => {
    const v = parseFloat(sheet.querySelector('#init-in').value);
    State.initialBalance = isNaN(v) ? null : v;
    closeModal(); render(); toast('已更新初始总额');
  };
}
function openKeyEdit() {
  const configured = State.keyConfigured && !State.simNoKey;
  const sheet = buildSheet('DeepSeek API Key', `
    <div class="field"><label>API Key</label>
      <input type="text" id="key-in" placeholder="sk-..." value="${configured?'sk-demo-****************':''}"></div>
    <div style="font-size:12px;color:var(--ink-3);margin-bottom:16px">Key 仅保存在本机，用于把识别到的文本发给 DeepSeek 做解析与分类。</div>
    <button class="btn" id="key-save">保存</button>
  `);
  sheet.querySelector('#key-save').onclick = () => {
    const v = sheet.querySelector('#key-in').value.trim();
    State.keyConfigured = !!v; State.simNoKey = false;
    document.getElementById('chk-nokey').checked = false;
    closeModal(); render(); toast(v ? 'Key 已保存' : 'Key 已清空');
  };
}

/* ---- R4 自定义分类编辑器（新增 / 编辑）----
   cat=null 为新增；否则编辑（仅自定义分类进得来）。onSaved 用于就地刷新分类管理列表。 */
function openCatEditor(dir, cat, onSaved) {
  const editing = !!cat;
  let d = dir || cat?.dir || 'expense';
  let icon = cat?.icon || CAT_ICON_CHOICES[0];
  let color = cat?.color || CAT_COLOR_CHOICES[0];
  const sheet = buildSheet(editing ? '编辑分类' : '新增自定义分类', `
    ${editing ? '' : `
    <div class="field"><label>方向</label>
      <div class="seg" id="ce-dir"><button data-d="expense" class="on">支出</button><button data-d="income">收入</button></div>
    </div>`}
    <div class="field"><label>名称</label><input type="text" id="ce-name" maxlength="6" value="${esc(cat?.label||'')}" placeholder="如 宠物、医疗、教育"></div>
    <div class="field"><label>图标</label><div class="pick-grid" id="ce-icons">
      ${CAT_ICON_CHOICES.map(ic => `<button class="pick ${ic===icon?'on':''}" data-ic="${ic}">${ic}</button>`).join('')}
    </div></div>
    <div class="field"><label>颜色</label><div class="pick-grid" id="ce-colors">
      ${CAT_COLOR_CHOICES.map(co => `<button class="pick color ${co===color?'on':''}" data-co="${co}" style="background:${co}"></button>`).join('')}
    </div></div>
    <button class="btn" id="ce-save">${editing?'保存修改':'创建分类'}</button>
    ${editing ? '<button class="btn ghost" id="ce-del" style="color:var(--warn)">删除这个分类</button>' : ''}
  `);
  const seg = sheet.querySelector('#ce-dir');
  if (seg) seg.querySelectorAll('button').forEach(b => b.onclick = () => { d = b.dataset.d; seg.querySelectorAll('button').forEach(x=>x.classList.toggle('on',x.dataset.d===d)); });
  sheet.querySelectorAll('#ce-icons .pick').forEach(b => b.onclick = () => { icon = b.dataset.ic; sheet.querySelectorAll('#ce-icons .pick').forEach(x=>x.classList.toggle('on',x.dataset.ic===icon)); });
  sheet.querySelectorAll('#ce-colors .pick').forEach(b => b.onclick = () => { color = b.dataset.co; sheet.querySelectorAll('#ce-colors .pick').forEach(x=>x.classList.toggle('on',x.dataset.co===color)); });

  sheet.querySelector('#ce-save').onclick = () => {
    const name = sheet.querySelector('#ce-name').value.trim();
    if (!name) return toast('请输入分类名称', true);
    if (editing) {
      updateCategory(d, cat.key, { label: name, icon, color });
      toast('分类已更新');
    } else {
      const created = addCategory(d, name, icon, color);
      if (!created) return toast('该方向已有同名分类', true);
      toast('已新增分类「' + name + '」');
    }
    closeModal(); if (onSaved) onSaved();
  };
  const del = sheet.querySelector('#ce-del');
  if (del) del.onclick = () => {
    const used = categoryUsageCount(cat.key);
    const msg = used > 0
      ? `有 ${used} 笔账单用了这个分类，删除后这些账单会转到「其他」。确定删除？`
      : '确定删除这个自定义分类？';
    confirmDialog('删除分类', msg, '删除', () => {
      if (used > 0) State.bills.forEach(b => { if (b.cat === cat.key) b.cat = '其他'; });
      deleteCategory(d, cat.key);
      closeModal(); render(); toast('分类已删除');
    }, '取消', null, true);
  };
}

/* ---------- 通用弹层 ---------- */
function buildSheet(title, innerHTML) {
  const overlay = el(`<div class="overlay"></div>`);
  const sheet = el(`<div class="sheet"><div class="grab"></div><div class="sheet-head">${esc(title)}</div>${innerHTML}</div>`);
  overlay.appendChild(sheet);
  overlay.onclick = e => { if (e.target === overlay) closeModal(); };
  modalRoot.appendChild(overlay);
  return sheet;
}
function confirmDialog(title, msg, okText, onOk, cancelText, onCancel, danger) {
  const overlay = el(`<div class="overlay center"></div>`);
  const dialog = el(`
    <div class="dialog">
      <div class="d-title">${esc(title)}</div>
      <div class="d-msg">${esc(msg)}</div>
      <div class="d-btns">
        <button class="btn secondary" id="d-cancel">${esc(cancelText||'取消')}</button>
        <button class="btn ${danger?'danger':''}" id="d-ok">${esc(okText)}</button>
      </div>
    </div>
  `);
  overlay.appendChild(dialog);
  modalRoot.appendChild(overlay);
  dialog.querySelector('#d-ok').onclick = onOk;
  dialog.querySelector('#d-cancel').onclick = () => { closeModal(); if (onCancel) onCancel(); };
}

/* ---------- 演示控制台 ---------- */
document.getElementById('btn-reset').onclick = () => { reset(); removeAllNotif(); ['chk-fail','chk-nokey','chk-multi','chk-nodate'].forEach(i=>{const c=document.getElementById(i);if(c)c.checked=false;}); currentTab='add'; render(); toast('已重置演示数据'); };
document.getElementById('btn-shortcut').onclick = () => { if (!State.onboarded) return toast('请先完成首次引导', true); if (needKeyBlocked()) return; if (State.simMulti) { _forceMultiOnce = true; recognizeFlow('screenshot','正在识别账单截图…','本地读取文字 → DeepSeek 解析多笔'); return; } runShortcutIntake(); };
document.getElementById('chk-fail').onchange = e => { State.simFail = e.target.checked; toast(e.target.checked?'已开启：识别将失败':'已关闭识别失败模拟'); };
document.getElementById('chk-nokey').onchange = e => { State.simNoKey = e.target.checked; if(currentTab==='mine') render(); toast(e.target.checked?'已开启：模拟未配置 Key':'已关闭'); };
document.getElementById('chk-multi').onchange = e => { State.simMulti = e.target.checked; toast(e.target.checked?'已开启：截图将识别多笔':'已关闭多笔模拟'); };
document.getElementById('chk-nodate').onchange = e => { State.simNoDate = e.target.checked; toast(e.target.checked?'已开启：识别不到消费日期':'已关闭'); };

/* ---------- 启动 ---------- */
render();
