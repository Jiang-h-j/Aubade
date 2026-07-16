/* ===== Aubade 原型 · 数据与状态（假数据，非真实持久化） ===== */

// 分类：运行时可增删改（R4）。isPreset=true 为预置分类，不可删、不可改名（可否改图标/色待确认，原型默认锁全部字段）。
// key 作为账单外键；自定义分类 key 用生成 id，避免与预置中文 key 冲突。
const CATS = {
  expense: [
    { key: '衣', label: '衣', icon: '👕', color: '#e8a0bf', isPreset: true },
    { key: '食', label: '食', icon: '🍜', color: '#f0a868', isPreset: true },
    { key: '住', label: '住', icon: '🏠', color: '#8fb8de', isPreset: true },
    { key: '行', label: '行', icon: '🚗', color: '#7fc8a9', isPreset: true },
    { key: '玩', label: '玩', icon: '🎮', color: '#b39ddb', isPreset: true },
    { key: '其他', label: '其他', icon: '📦', color: '#b0b7c3', isPreset: true },
  ],
  income: [
    { key: '工作', label: '工作', icon: '💼', color: '#6bbf8a', isPreset: true },
    { key: '其他收入', label: '其他收入', icon: '🎁', color: '#9ccc9c', isPreset: true },
  ],
};

// 自定义分类可选图标/颜色（新增/编辑时挑选）
const CAT_ICON_CHOICES = ['🐾','🎓','💊','🎁','✈️','📚','🏋️','🎵','🍼','🐶','💄','🔧','🌱','☕️','🎨','🏦'];
const CAT_COLOR_CHOICES = ['#e8785c','#f0a868','#e8a0bf','#b39ddb','#8fb8de','#7fc8a9','#6bbf8a','#c0a080'];

function catId() { return 'c' + Math.random().toString(36).slice(2, 8); }

// 新增自定义分类；重名（同方向）返回 null
function addCategory(dir, label, icon, color) {
  const name = (label || '').trim();
  if (!name) return null;
  if (CATS[dir].some(c => c.label === name)) return null;
  const c = { key: catId(), label: name, icon: icon || '🏷', color: color || '#b0b7c3', isPreset: false };
  CATS[dir].push(c);
  return c;
}
// 编辑自定义分类（预置分类由 UI 拦截，这里防御性再挡一次）
function updateCategory(dir, key, patch) {
  const c = CATS[dir].find(x => x.key === key);
  if (!c || c.isPreset) return false;
  Object.assign(c, patch);
  return true;
}
// 删除自定义分类；被账单引用时返回引用数，交给 UI 决定策略
function categoryUsageCount(key) { return State.bills.filter(b => b.cat === key).length; }
function deleteCategory(dir, key) {
  const c = CATS[dir].find(x => x.key === key);
  if (!c || c.isPreset) return false;
  CATS[dir] = CATS[dir].filter(x => x.key !== key);
  return true;
}

// 默认演示账单（重置时恢复到此）
function seedBills() {
  return [
    { id: id(), amount: 35,   dir: 'expense', cat: '食',    time: '2026-07-10 12:30', merchant: '楼下面馆', note: '午餐', source: 'manual' },
    { id: id(), amount: 20,   dir: 'expense', cat: '行',    time: '2026-07-10 09:05', merchant: '滴滴出行', note: '打车', source: 'text' },
    { id: id(), amount: 299,  dir: 'expense', cat: '衣',    time: '2026-07-09 20:12', merchant: '优衣库',   note: '', source: 'screenshot' },
    { id: id(), amount: 128,  dir: 'expense', cat: '食',    time: '2026-07-09 19:00', merchant: '永辉超市', note: '买菜', source: 'text' },
    { id: id(), amount: 8000, dir: 'income',  cat: '工作',  time: '2026-07-09 10:00', merchant: '公司',     note: '工资', source: 'text' },
    { id: id(), amount: 60,   dir: 'expense', cat: '玩',    time: '2026-07-08 21:30', merchant: '万达影城', note: '电影', source: 'manual' },
    { id: id(), amount: 1200, dir: 'expense', cat: '住',    time: '2026-07-08 08:00', merchant: '房租',     note: '', source: 'manual' },
    // —— 本月更早几天（让"日/周"翻页与趋势有内容）——
    { id: id(), amount: 68,   dir: 'expense', cat: '玩',    time: '2026-07-06 15:20', merchant: '喜茶',     note: '下午茶', source: 'manual' },
    { id: id(), amount: 45,   dir: 'expense', cat: '食',    time: '2026-07-03 12:10', merchant: '沙县小吃', note: '', source: 'text' },
    { id: id(), amount: 200,  dir: 'expense', cat: '行',    time: '2026-07-01 08:30', merchant: '中石化',   note: '加油', source: 'screenshot' },
    // —— 上月（让"月"翻页有内容）——
    { id: id(), amount: 88,   dir: 'expense', cat: '食',    time: '2026-06-28 19:30', merchant: '海底捞',   note: '聚餐', source: 'manual' },
    { id: id(), amount: 520,  dir: 'expense', cat: '衣',    time: '2026-06-18 14:00', merchant: '耐克',     note: '', source: 'screenshot' },
    { id: id(), amount: 6500, dir: 'income',  cat: '工作',  time: '2026-06-10 10:00', merchant: '公司',     note: '6月工资', source: 'text' },
    // —— 去年（让"年"翻页有内容）——
    { id: id(), amount: 300,  dir: 'expense', cat: '玩',    time: '2025-12-20 20:00', merchant: 'KTV',      note: '年会后', source: 'manual' },
  ];
}

// 模拟识别结果：不同入口给不同示例
const MOCK_RECOGNIZE = {
  screenshot: { amount: 88.5, dir: 'expense', cat: '食',  time: '2026-07-10 13:10', merchant: '星巴克', note: '',
    raw: '[截图本地识别文字]\n星巴克咖啡\n实付金额 ¥88.50\n2026-07-10 13:10\n交易成功' },
  voice: { amount: 20, dir: 'expense', cat: '行', time: '2026-07-10 14:00', merchant: '', note: '打车',
    raw: '[语音转文字]\n"打车花了 20 块"' },
  text: { amount: 256, dir: 'expense', cat: '其他', time: '2026-07-10 15:22', merchant: '京东商城', note: '',
    raw: '【工商银行】您尾号1234的储蓄卡2026年07月10日15:22支出人民币256.00元，商户京东商城，余额12089.00元。' },
};

// 模拟"快捷指令随手截图"送入的一张支付结果图（后台入账用）
const MOCK_SHORTCUT_SHOT = { amount: 42.8, dir: 'expense', cat: '食', time: '2026-07-10 18:36', merchant: '瑞幸咖啡', note: '',
  raw: '[快捷指令截图 · 本地识别文字]\n微信支付\n瑞幸咖啡(国贸店)\n-42.80\n2026-07-10 18:36\n支付成功' };

// R5 截图多笔：一张账单截图里识别出多笔消费。
// 第 2 笔故意 dateUnknown=true（DeepSeek 未解析出日期），用于演示 R2 兜底提示与"日期未识别"高亮。
const MOCK_MULTI_SHOT = {
  raw: '[截图 · 本地识别文字]\n账单明细\n06-03 星巴克   ¥38.00\n盒马鲜生   ¥126.50\n06-03 滴滴出行 ¥24.00',
  items: [
    { amount: 38,    dir: 'expense', cat: '食', time: '2026-06-03 09:12', merchant: '星巴克',   note: '', dateUnknown: false },
    { amount: 126.5, dir: 'expense', cat: '食', time: '2026-07-10 00:00', merchant: '盒马鲜生', note: '', dateUnknown: true  },
    { amount: 24,    dir: 'expense', cat: '行', time: '2026-06-03 21:40', merchant: '滴滴出行', note: '', dateUnknown: false },
  ],
};

const SAMPLE_TEXT = '【工商银行】您尾号1234的储蓄卡2026年07月10日15:22支出人民币256.00元，商户京东商城，余额12089.00元。';

// 演示"今天"（真实 App 用系统日期；原型固定，保证翻页可预期）
const TODAY = '2026-07-10';


// ---- 运行时状态 ----
// 默认进入"已使用一段时间"的状态：有初始总额、示例账单、预算，
// 这样一进来就能看到账单/统计/超支的完整样子。
// 点演示控制台的"重置数据"才回到首次引导空态。
const State = {
  onboarded: true,
  initialBalance: 12000,  // 初始总额（此刻所有账户合计的起点）
  keyConfigured: true,    // DeepSeek Key 是否已配置（演示默认已配）
  budgets: { week: 800, month: 1500 },
  bills: seedBills(),
  // 演示开关
  simFail: false,
  simNoKey: false,
  simMulti: false,     // R5：截图识别出多笔
  simNoDate: false,    // R2：识别不到消费日期（单笔入口）
};

function id() { return 'b' + Math.random().toString(36).slice(2, 9); }

// 回到"首次使用"空态：无引导、无初始总额、无账单
function reset() {
  State.onboarded = false;
  State.initialBalance = null;
  State.keyConfigured = true;
  State.budgets = { week: 800, month: 1500 };
  State.bills = [];
  State.simFail = false;
  State.simNoKey = false;
  State.simMulti = false;
  State.simNoDate = false;
  // 清掉运行时新增的自定义分类，恢复到纯预置
  CATS.expense = CATS.expense.filter(c => c.isPreset);
  CATS.income = CATS.income.filter(c => c.isPreset);
}

// ---- 计算 ----
function sumBy(pred) {
  return State.bills.filter(pred).reduce((s, b) => s + b.amount, 0);
}
function totalExpense() { return sumBy(b => b.dir === 'expense'); }
function totalIncome()  { return sumBy(b => b.dir === 'income'); }

function remaining() {
  if (State.initialBalance == null) return null;
  return State.initialBalance + totalIncome() - totalExpense();
}

// 本月/本周口径（真实按当月、当周聚合，供账单页汇总卡与统计默认档使用）
function monthExpense() { const r = periodRange('month', 0); return rangeSum(billsInRange(r.start, r.end), 'expense'); }
function monthIncome()  { const r = periodRange('month', 0); return rangeSum(billsInRange(r.start, r.end), 'income'); }
function weekExpense()  { const r = periodRange('week', 0); return rangeSum(billsInRange(r.start, r.end), 'expense'); }

/* ============ 统计页：日/周/月/年 统一时间维度 ============ */
// 纯日期工具（不依赖 Date.now，全部基于传入的 'YYYY-MM-DD' 字符串）
function ymd(s) { const [y,m,d] = s.slice(0,10).split('-').map(Number); return { y, m, d }; }
function pad(n) { return String(n).padStart(2, '0'); }
function daysInMonth(y, m) { return [31, (y%4===0&&y%100!==0)||y%400===0?29:28, 31,30,31,30,31,31,30,31,30,31][m-1]; }
// 计算某日是周几（0=周日…6=周六），Zeller 变体，避免用 Date
function weekdayOf(y, m, d) {
  if (m < 3) { m += 12; y -= 1; }
  const k = y % 100, j = Math.floor(y / 100);
  const h = (d + Math.floor(13*(m+1)/5) + k + Math.floor(k/4) + Math.floor(j/4) + 5*j) % 7;
  return (h + 6) % 7; // 转成 0=周日
}
const WK_CN = ['日','一','二','三','四','五','六'];

// 给定粒度 grain 和相对今天的偏移 offset（0=当前，-1=上一个），
// 返回该时间桶的 {start,end}(闭区间 YYYY-MM-DD)、标题、副标题
function periodRange(grain, offset) {
  const t = ymd(TODAY);
  if (grain === 'day') {
    // 以今天为基准前后推 offset 天
    let y = t.y, m = t.m, d = t.d + offset;
    while (d < 1) { m--; if (m < 1) { m = 12; y--; } d += daysInMonth(y, m); }
    while (d > daysInMonth(y, m)) { d -= daysInMonth(y, m); m++; if (m > 12) { m = 1; y++; } }
    const iso = `${y}-${pad(m)}-${pad(d)}`;
    const wd = weekdayOf(y, m, d);
    return { start: iso, end: iso, title: `${m}月${d}日`, sub: `周${WK_CN[wd]}`, y, m, d };
  }
  if (grain === 'week') {
    // 本周一为基准，offset 周
    const wd = weekdayOf(t.y, t.m, t.d);       // 0=周日
    const mondayShift = (wd === 0 ? -6 : 1 - wd); // 回到本周一
    // 用序号运算：把日期转成"自纪元的天序"太重，改用逐日回退
    const base = addDays(TODAY, mondayShift + offset * 7);
    const end = addDays(base, 6);
    const bs = ymd(base), es = ymd(end);
    const title = `${bs.m}月${bs.d}日 - ${es.m}月${es.d}日`;
    return { start: base, end, title, sub: offset === 0 ? '本周' : `${-offset}周前`, };
  }
  if (grain === 'month') {
    let y = t.y, m = t.m + offset;
    while (m < 1) { m += 12; y--; }
    while (m > 12) { m -= 12; y++; }
    const start = `${y}-${pad(m)}-01`;
    const end = `${y}-${pad(m)}-${pad(daysInMonth(y, m))}`;
    return { start, end, title: `${y}年${m}月`, sub: offset === 0 ? '本月' : '', y, m };
  }
  // year
  const y = t.y + offset;
  return { start: `${y}-01-01`, end: `${y}-12-31`, title: `${y}年`, sub: offset === 0 ? '今年' : '', y };
}
// 日期加减（闭区间字符串运算，避免 Date）
function addDays(iso, delta) {
  let { y, m, d } = ymd(iso); d += delta;
  while (d < 1) { m--; if (m < 1) { m = 12; y--; } d += daysInMonth(y, m); }
  while (d > daysInMonth(y, m)) { d -= daysInMonth(y, m); m++; if (m > 12) { m = 1; y++; } }
  return `${y}-${pad(m)}-${pad(d)}`;
}
// 未来方向是否已到头（不允许翻到今天之后）
function isFuture(grain, offset) { return offset >= 0 ? offset > 0 : false; }

// 取某区间内的账单
function billsInRange(start, end) {
  return State.bills.filter(b => { const d = b.time.slice(0,10); return d >= start && d <= end; });
}
// 区间内支出/收入合计
function rangeSum(bills, dir) { return bills.filter(b => b.dir===dir).reduce((s,b)=>s+b.amount,0); }
// 区间内分类占比
function rangeCatBreakdown(bills, dir='expense') {
  const map = {};
  bills.filter(b => b.dir === dir).forEach(b => { map[b.cat] = (map[b.cat]||0) + b.amount; });
  const total = Object.values(map).reduce((s,v)=>s+v,0) || 1;
  return Object.entries(map).map(([cat,val]) => ({ cat, val, pct: Math.round(val/total*100) }))
    .sort((a,b)=>b.val-a.val);
}
// 生成趋势序列：横轴桶跟随粒度
//  day  → 当天 24 小时不合适，用"当周7天"体现走势
//  week → 当周 7 天
//  month→ 当月每日
//  year → 当年 12 月
function trendSeries(grain, offset) {
  const r = periodRange(grain, offset);
  const expOf = (s,e) => rangeSum(billsInRange(s,e), 'expense');
  if (grain === 'year') {
    const y = r.y, labels = [], values = [];
    for (let m=1; m<=12; m++) { labels.push(m+'月'); values.push(expOf(`${y}-${pad(m)}-01`, `${y}-${pad(m)}-${pad(daysInMonth(y,m))}`)); }
    return { labels, values };
  }
  if (grain === 'month') {
    const y = r.y, m = r.m, n = daysInMonth(y,m), labels = [], values = [];
    for (let d=1; d<=n; d++) { const iso = `${y}-${pad(m)}-${pad(d)}`; values.push(expOf(iso,iso)); labels.push(d%5===1||d===n?`${m}/${d}`:''); }
    return { labels, values };
  }
  // day / week 都展示"所在周的 7 天"
  const weekR = grain === 'week' ? r : periodRange('week', weekOffsetOfDay(r.start));
  const labels = [], values = [];
  for (let i=0;i<7;i++){ const iso = addDays(weekR.start,i); const dd = ymd(iso); labels.push(`${dd.m}/${dd.d}`); values.push(expOf(iso,iso)); }
  return { labels, values };
}
// 某天属于相对今天第几周（供 day 档趋势复用周视图）
function weekOffsetOfDay(iso) {
  const t = ymd(TODAY); const wd = weekdayOf(t.y,t.m,t.d);
  const thisMon = addDays(TODAY, wd===0?-6:1-wd);
  const dw = ymd(iso); const wdD = weekdayOf(dw.y,dw.m,dw.d);
  const dMon = addDays(iso, wdD===0?-6:1-wdD);
  // 计算两个周一相差多少周
  let diff = 0, cur = dMon;
  if (cur < thisMon) { while (cur < thisMon) { cur = addDays(cur,7); diff--; } }
  else { while (cur > thisMon) { cur = addDays(cur,-7); diff++; } }
  return diff;
}

function catBreakdown(dir = 'expense') {
  const map = {};
  State.bills.filter(b => b.dir === dir).forEach(b => { map[b.cat] = (map[b.cat] || 0) + b.amount; });
  const total = Object.values(map).reduce((s, v) => s + v, 0) || 1;
  return Object.entries(map)
    .map(([cat, val]) => ({ cat, val, pct: Math.round(val / total * 100) }))
    .sort((a, b) => b.val - a.val);
}

function catMeta(key) {
  const all = [...CATS.expense, ...CATS.income];
  return all.find(c => c.key === key) || { label: key, icon: '📦', color: '#b0b7c3' };
}
function catLabel(key) { return catMeta(key).label; }
function catIcon(key) { return catMeta(key).icon; }
function catColor(key) { return catMeta(key).color; }

function money(n) {
  return n.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
