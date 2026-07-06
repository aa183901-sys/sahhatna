/**
 * صحتنا - Clinic Dashboard Logic
 * Handles clinic login, bookings, calendar, doctors, schedule, and reminders.
 * All SahatnaDB calls are async (Supabase or localStorage).
 */

// ---- State ---------------------------------------------------------------
let currentClinic = null;
let currentClinicUser = null;
let calendarDate = new Date();
let selectedCalendarDay = null;

// ---- Utilities -----------------------------------------------------------
function showToast(message, type = 'success') {
  const container = document.getElementById('toastContainer');
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transition = 'opacity 0.3s';
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

function formatPrice(price) {
  return new Intl.NumberFormat('ar-IQ').format(price) + ' د.ع';
}

function getStatusBadge(status) {
  const badges = {
    confirmed: '<span class="badge badge-info">مؤكد</span>',
    completed: '<span class="badge badge-success">مكتمل</span>',
    cancelled: '<span class="badge badge-danger">ملغي</span>',
  };
  return badges[status] || badges.confirmed;
}

function getStatusLabel(status) {
  const labels = { confirmed: 'مؤكد', completed: 'مكتمل', cancelled: 'ملغي' };
  return labels[status] || status;
}

function getServiceLabel(service) {
  const labels = { clinic: 'زيارة عيادة', video: 'استشارة فيديو', home: 'زيارة منزلية' };
  return labels[service] || service;
}

// ---- Auth ----------------------------------------------------------------
async function handleClinicLogin(event) {
  event.preventDefault();
  const username = document.getElementById('loginUsername').value.trim();
  const password = document.getElementById('loginPassword').value.trim();

  const result = await SahatnaDB.clinicLogin(username, password);
  if (result) {
    currentClinicUser = result.user;
    currentClinic = result.clinic;
    sessionStorage.setItem('sahatna_clinic', JSON.stringify({ userId: result.user.id, clinicId: result.clinic.id }));
    showDashboard();
    showToast('تم تسجيل الدخول بنجاح', 'success');
  } else {
    showToast('اسم المستخدم أو كلمة المرور غير صحيحة', 'error');
  }
}

async function clinicLogout() {
  await SahatnaDB.signOut();
  sessionStorage.removeItem('sahatna_clinic');
  currentClinic = null;
  currentClinicUser = null;
  document.getElementById('dashboard').classList.add('hidden');
  document.getElementById('loginScreen').classList.remove('hidden');
  showToast('تم تسجيل الخروج', 'info');
}

async function checkClinicSession() {
  const saved = sessionStorage.getItem('sahatna_clinic');
  if (saved) {
    try {
      const { userId, clinicId } = JSON.parse(saved);
      const db = await SahatnaDB.load();
      const user = db.clinicUsers ? db.clinicUsers.find((u) => u.id === userId) : { id: userId, clinicId, name: 'مدير العيادة' };
      const clinic = db.clinics.find((c) => c.id === clinicId);
      if (user && clinic) {
        currentClinicUser = user;
        currentClinic = clinic;
        showDashboard();
      }
    } catch (e) {
      sessionStorage.removeItem('sahatna_clinic');
    }
  }
}

// ---- Dashboard -----------------------------------------------------------
async function showDashboard() {
  document.getElementById('loginScreen').classList.add('hidden');
  document.getElementById('dashboard').classList.remove('hidden');

  document.getElementById('clinicNameHeader').textContent = currentClinic.name;
  document.getElementById('welcomeMsg').textContent = 'مرحباً، ' + (currentClinicUser.name || 'مدير العيادة');
  const city = await SahatnaDB.getCity(currentClinic.cityId);
  document.getElementById('clinicInfo').textContent =
    `${currentClinic.area}، ${city ? city.name : ''} • ${currentClinic.phone}`;

  await renderClinicStats();
  await populateBookingFilters();
  await renderBookingsList();
  await renderClinicDoctors();
  await populateScheduleDoctorSelect();
  await renderReminders();
  await updateRemindersBadge();
}

async function renderClinicStats() {
  const bookings = await SahatnaDB.getBookingsByClinic(currentClinic.id);
  const today = new Date().toISOString().slice(0, 10);
  const db = await SahatnaDB.load();
  const doctors = db.doctors.filter((d) => d.clinicId === currentClinic.id);

  document.getElementById('statTodayBookings').textContent =
    bookings.filter((b) => b.date === today).length;
  document.getElementById('statTotalBookings').textContent = bookings.length;
  document.getElementById('statDoctorsCount').textContent = doctors.length;
  document.getElementById('statCompleted').textContent =
    bookings.filter((b) => b.status === 'completed').length;
  document.getElementById('statCancelled').textContent =
    bookings.filter((b) => b.status === 'cancelled').length;
}

// ---- Tabs ----------------------------------------------------------------
function switchTab(tabName) {
  document.querySelectorAll('.tab-content').forEach((t) => t.classList.add('hidden'));
  document.querySelectorAll('.tab-btn').forEach((b) => b.classList.remove('active'));

  document.getElementById('tab-' + tabName).classList.remove('hidden');
  document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');

  if (tabName === 'calendar') renderCalendar();
  if (tabName === 'schedule') loadDoctorSchedule();
  if (tabName === 'reminders') renderReminders();
}

// ---- Bookings List -------------------------------------------------------
async function populateBookingFilters() {
  const db = await SahatnaDB.load();
  const doctors = db.doctors.filter((d) => d.clinicId === currentClinic.id);
  const select = document.getElementById('bookingFilterDoctor');
  select.innerHTML = '<option value="">كل الأطباء</option>';
  doctors.forEach((d) => {
    const opt = document.createElement('option');
    opt.value = d.id;
    opt.textContent = d.name;
    select.appendChild(opt);
  });
}

async function renderBookingsList() {
  let bookings = await SahatnaDB.getBookingsByClinic(currentClinic.id);
  const statusFilter = document.getElementById('bookingFilterStatus').value;
  const doctorFilter = document.getElementById('bookingFilterDoctor').value;

  if (statusFilter) bookings = bookings.filter((b) => b.status === statusFilter);
  if (doctorFilter) bookings = bookings.filter((b) => b.doctorId === doctorFilter);

  const list = document.getElementById('bookingsList');
  const db = await SahatnaDB.load();

  if (bookings.length === 0) {
    list.innerHTML = `
      <div class="empty-state">
        <div class="empty-state-icon">📅</div>
        <h4 class="text-lg font-bold text-gray-500 mb-2">لا توجد حجوزات</h4>
        <p class="text-gray-400">ستظهر الحجوزات هنا عند قيام المرضى بالحجز</p>
      </div>
    `;
    return;
  }

  list.innerHTML = bookings
    .map((b) => {
      const doctor = db.doctors.find((d) => d.id === b.doctorId);
      const specialty = doctor ? db.specialties.find((s) => s.id === doctor.specialtyId) : null;
      const dayName = SahatnaDB.getDayName(new Date(b.date + 'T00:00:00').getDay());
      const timeParts = b.time.split(':').map(Number);

      return `
        <div class="booking-item status-${b.status} animate-fade-in">
          <div class="flex items-start justify-between gap-3 flex-wrap">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 mb-1">
                <span class="font-bold text-gray-800">${b.patientName}</span>
                ${getStatusBadge(b.status)}
              </div>
              <div class="text-sm text-gray-500 space-y-1">
                <p>👨‍⚕️ ${doctor ? doctor.name : ''} - ${specialty ? specialty.name : ''}</p>
                <p>📅 ${dayName} ${b.date} • ⏰ ${SahatnaDB.formatTime(timeParts[0], timeParts[1])}</p>
                <p>📞 ${b.patientPhone} ${b.patientAge ? '• العمر: ' + b.patientAge : ''}</p>
                <p>🏥 ${getServiceLabel(b.service)} • 💰 ${formatPrice(b.price)}</p>
                ${b.patientNotes ? `<p class="text-gray-400 italic">📝 ${b.patientNotes}</p>` : ''}
              </div>
            </div>
            <div class="flex flex-col gap-2 flex-shrink-0">
              ${b.status === 'confirmed'
                ? `
                <button onclick="updateBookingStatus('${b.id}', 'completed')" class="btn-success text-xs">✓ إكمال</button>
                <button onclick="cancelBooking('${b.id}')" class="btn-danger text-xs">✕ إلغاء</button>
              `
                : ''}
              ${b.status === 'completed' ? `<span class="text-xs text-success font-semibold">✓ تمت الزيارة</span>` : ''}
              ${b.status === 'cancelled' ? `<span class="text-xs text-danger font-semibold">✕ ملغي</span>` : ''}
            </div>
          </div>
        </div>
      `;
    })
    .join('');
}

async function updateBookingStatus(bookingId, status) {
  await SahatnaDB.updateBookingStatus(bookingId, status);
  await renderBookingsList();
  await renderClinicStats();
  showToast(`تم تحديث حالة الحجز إلى: ${getStatusLabel(status)}`, 'success');
}

async function cancelBooking(bookingId) {
  if (confirm('هل أنت متأكد من إلغاء هذا الحجز؟')) {
    await SahatnaDB.updateBookingStatus(bookingId, 'cancelled');
    await renderBookingsList();
    await renderClinicStats();
    showToast('تم إلغاء الحجز', 'info');
  }
}

// ---- Calendar ------------------------------------------------------------
async function renderCalendar() {
  const year = calendarDate.getFullYear();
  const month = calendarDate.getMonth();
  const monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  document.getElementById('calendarMonthLabel').textContent = `${monthNames[month]} ${year}`;

  const firstDay = new Date(year, month, 1).getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const daysInPrevMonth = new Date(year, month, 0).getDate();
  const today = new Date().toISOString().slice(0, 10);

  const bookings = await SahatnaDB.getBookingsByClinic(currentClinic.id);
  const dayNames = ['أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];

  let html = '';
  dayNames.forEach((d) => {
    html += `<div class="text-center text-xs font-bold text-gray-500 py-2">${d}</div>`;
  });

  for (let i = firstDay - 1; i >= 0; i--) {
    html += `<div class="cal-day other-month text-center text-sm">${daysInPrevMonth - i}</div>`;
  }

  for (let d = 1; d <= daysInMonth; d++) {
    const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
    const dayBookings = bookings.filter((b) => b.date === dateStr);
    const isToday = dateStr === today;

    html += `
      <div class="cal-day ${isToday ? 'today' : ''} cursor-pointer hover:border-primary transition" onclick="selectCalendarDay('${dateStr}')">
        <div class="text-sm font-semibold ${isToday ? 'text-primary' : 'text-gray-700'}">${d}</div>
        ${dayBookings.length > 0 ? `<div class="mt-1"><span class="badge badge-primary text-xs">${dayBookings.length} حجز</span></div>` : ''}
      </div>
    `;
  }

  const totalCells = firstDay + daysInMonth;
  const remaining = (7 - (totalCells % 7)) % 7;
  for (let i = 1; i <= remaining; i++) {
    html += `<div class="cal-day other-month text-center text-sm">${i}</div>`;
  }

  document.getElementById('calendarGrid').innerHTML = html;

  if (selectedCalendarDay) {
    renderCalendarDayDetail(selectedCalendarDay);
  }
}

function changeCalendarMonth(delta) {
  calendarDate.setMonth(calendarDate.getMonth() + delta);
  renderCalendar();
}

function selectCalendarDay(dateStr) {
  selectedCalendarDay = dateStr;
  renderCalendarDayDetail(dateStr);
}

async function renderCalendarDayDetail(dateStr) {
  const bookings = (await SahatnaDB.getBookingsByClinic(currentClinic.id)).filter((b) => b.date === dateStr);
  const dayName = SahatnaDB.getDayName(new Date(dateStr + 'T00:00:00').getDay());
  const container = document.getElementById('calendarDayDetail');
  const db = await SahatnaDB.load();

  if (bookings.length === 0) {
    container.innerHTML = `<div class="bg-gray-50 rounded-xl p-4 text-center text-gray-400">لا توجد حجوزات في ${dayName} ${dateStr}</div>`;
    return;
  }

  container.innerHTML = `
    <h4 class="font-bold text-gray-800 mb-3">حجوزات ${dayName} ${dateStr} (${bookings.length})</h4>
    <div class="space-y-2">
      ${bookings.map((b) => {
        const doctor = db.doctors.find((d) => d.id === b.doctorId);
        const timeParts = b.time.split(':').map(Number);
        return `
          <div class="booking-item status-${b.status}">
            <div class="flex items-center justify-between">
              <div>
                <span class="font-bold text-sm">${b.patientName}</span>
                <span class="text-gray-400 text-sm"> - ${doctor ? doctor.name : ''}</span>
              </div>
              <div class="flex items-center gap-2">
                <span class="text-sm text-gray-500">⏰ ${SahatnaDB.formatTime(timeParts[0], timeParts[1])}</span>
                ${getStatusBadge(b.status)}
              </div>
            </div>
          </div>
        `;
      }).join('')}
    </div>
  `;
}

// ---- Doctors Tab ---------------------------------------------------------
async function renderClinicDoctors() {
  const db = await SahatnaDB.load();
  const doctors = db.doctors.filter((d) => d.clinicId === currentClinic.id);
  const list = document.getElementById('doctorsListClinic');

  if (doctors.length === 0) {
    list.innerHTML = `<div class="col-span-full empty-state"><div class="empty-state-icon">👨‍⚕️</div><p class="text-gray-400">لا يوجد أطباء مسجلين في عيادتك</p></div>`;
    return;
  }

  const cards = [];
  for (const d of doctors) {
    const specialty = db.specialties.find((s) => s.id === d.specialtyId);
    const docBookings = await SahatnaDB.getBookingsByDoctor(d.id);
    const completed = docBookings.filter((b) => b.status === 'completed').length;
    const revenue = docBookings.filter((b) => b.status === 'completed').reduce((sum, b) => sum + b.price, 0);

    cards.push(`
      <div class="border border-gray-200 rounded-2xl p-4 bg-white">
        <div class="flex gap-3">
          <img src="${d.photo}" class="w-16 h-16 rounded-xl object-cover" />
          <div class="flex-1">
            <div class="flex items-center gap-2">
              <h4 class="font-bold text-gray-800">${d.name}</h4>
              ${d.verified ? '<span class="verified-badge">✓</span>' : ''}
            </div>
            <p class="text-sm text-primary">${specialty ? specialty.name : ''}</p>
            <p class="text-xs text-gray-500 mt-1">خبرة ${d.experienceYears} سنة • ⭐ ${d.rating} (${d.reviewsCount})</p>
          </div>
        </div>
        <div class="grid grid-cols-3 gap-2 mt-3 pt-3 border-t border-gray-100 text-center">
          <div><p class="text-xs text-gray-400">السعر</p><p class="font-bold text-sm text-primary">${formatPrice(d.price)}</p></div>
          <div><p class="text-xs text-gray-400">حجوزات</p><p class="font-bold text-sm">${docBookings.length}</p></div>
          <div><p class="text-xs text-gray-400">الإيرادات</p><p class="font-bold text-sm text-success">${formatPrice(revenue)}</p></div>
        </div>
      </div>
    `);
  }
  list.innerHTML = cards.join('');
}

// ---- Add Doctor (Self-service) ------------------------------------------
function showAddDoctorForm() {
  const form = document.getElementById('addDoctorForm');
  form.classList.remove('hidden');
  populateDoctorSpecialtySelect();
  form.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function hideAddDoctorForm() {
  document.getElementById('addDoctorForm').classList.add('hidden');
}

async function populateDoctorSpecialtySelect() {
  const db = await SahatnaDB.load();
  const select = document.getElementById('newDoctorSpecialty');
  select.innerHTML = '<option value="">اختر التخصص...</option>';
  db.specialties.forEach((s) => {
    const opt = document.createElement('option');
    opt.value = s.id;
    opt.textContent = `${s.icon} ${s.name}`;
    select.appendChild(opt);
  });
}

async function handleAddDoctor(event) {
  event.preventDefault();

  const name = document.getElementById('newDoctorName').value.trim();
  const nameEn = document.getElementById('newDoctorNameEn').value.trim();
  const specialtyId = document.getElementById('newDoctorSpecialty').value;
  const gender = document.getElementById('newDoctorGender').value;
  const experienceYears = parseInt(document.getElementById('newDoctorExperience').value) || 0;
  const qualifications = document.getElementById('newDoctorQualifications').value.trim();
  const bio = document.getElementById('newDoctorBio').value.trim();
  const price = parseInt(document.getElementById('newDoctorPrice').value);

  // Validate required fields
  if (!name) {
    showToast('يرجى إدخال اسم الطبيب', 'error');
    return;
  }
  if (!specialtyId) {
    showToast('يرجى اختيار التخصص', 'error');
    return;
  }
  if (!price || price <= 0) {
    showToast('يرجى إدخال سعر صحيح', 'error');
    return;
  }

  // Build services array from checkboxes
  const services = [];
  if (document.getElementById('serviceClinic').checked) services.push('clinic');
  if (document.getElementById('serviceVideo').checked) services.push('video');
  if (document.getElementById('serviceHome').checked) services.push('home');
  if (services.length === 0) services.push('clinic');

  // Generate avatar URL based on name (same pattern as existing doctors)
  const avatarName = encodeURIComponent(nameEn || name);
  const bgColor = gender === 'female' ? 'db2777' : '0d9488';
  const photo = `https://ui-avatars.com/api/?name=${avatarName}&background=${bgColor}&color=fff&size=200`;

  const doctorData = {
    name,
    nameEn: nameEn || undefined,
    specialtyId,
    clinicId: currentClinic.id,
    photo,
    bio,
    qualifications,
    experienceYears,
    price,
    gender,
    languages: ['العربية'],
    services,
  };

  try {
    await SahatnaDB.addDoctor(doctorData);
    showToast('تمت إضافة الطبيب بنجاح', 'success');
    hideAddDoctorForm();
    await renderClinicDoctors();
    await populateScheduleDoctorSelect();
    await renderClinicStats();
  } catch (e) {
    showToast('حدث خطأ أثناء إضافة الطبيب: ' + e.message, 'error');
  }
}

// ---- Schedule Management -------------------------------------------------
async function populateScheduleDoctorSelect() {
  const db = await SahatnaDB.load();
  const doctors = db.doctors.filter((d) => d.clinicId === currentClinic.id);
  const select = document.getElementById('scheduleDoctorSelect');
  select.innerHTML = '<option value="">اختر طبيب...</option>';
  doctors.forEach((d) => {
    const opt = document.createElement('option');
    opt.value = d.id;
    opt.textContent = d.name;
    select.appendChild(opt);
  });
}

async function loadDoctorSchedule() {
  const doctorId = document.getElementById('scheduleDoctorSelect').value;
  const editor = document.getElementById('scheduleEditor');

  if (!doctorId) {
    editor.innerHTML = '<p class="text-gray-400 text-center py-8">اختر طبيباً لتعديل دوامه</p>';
    return;
  }

  const schedule = await SahatnaDB.getSchedule(doctorId);
  const dayNames = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  const slotDuration = schedule ? schedule.slotDuration : 30;

  let html = `
    <div class="bg-gray-50 rounded-xl p-4">
      <div class="mb-4">
        <label class="block text-sm font-semibold text-gray-600 mb-1">مدة الموعد (دقيقة)</label>
        <select id="slotDuration" class="form-input max-w-[120px]">
          <option value="15" ${slotDuration === 15 ? 'selected' : ''}>15 دقيقة</option>
          <option value="20" ${slotDuration === 20 ? 'selected' : ''}>20 دقيقة</option>
          <option value="30" ${slotDuration === 30 ? 'selected' : ''}>30 دقيقة</option>
          <option value="45" ${slotDuration === 45 ? 'selected' : ''}>45 دقيقة</option>
          <option value="60" ${slotDuration === 60 ? 'selected' : ''}>60 دقيقة</option>
        </select>
      </div>
      <div class="space-y-2">
  `;

  for (let day = 0; day < 7; day++) {
    const daySlot = schedule ? schedule.slots.find((s) => s.day === day) : null;
    const checked = daySlot ? 'checked' : '';
    const startVal = daySlot ? daySlot.start : '09:00';
    const endVal = daySlot ? daySlot.end : '17:00';

    html += `
      <div class="flex items-center gap-3 bg-white rounded-lg p-3 border border-gray-200">
        <label class="flex items-center gap-2 cursor-pointer min-w-[80px]">
          <input type="checkbox" class="day-checkbox day-${day}" ${checked} onchange="toggleDayRow(${day})" />
          <span class="font-semibold text-sm">${dayNames[day]}</span>
        </label>
        <div class="flex items-center gap-2 ${daySlot ? '' : 'opacity-40'}" id="day-times-${day}">
          <input type="time" value="${startVal}" class="form-input day-start-${day}" ${daySlot ? '' : 'disabled'} />
          <span class="text-gray-400">إلى</span>
          <input type="time" value="${endVal}" class="form-input day-end-${day}" ${daySlot ? '' : 'disabled'} />
        </div>
      </div>
    `;
  }

  html += `</div><button onclick="saveSchedule('${doctorId}')" class="btn-primary w-full mt-4">حفظ الدوام</button></div>`;
  editor.innerHTML = html;
}

function toggleDayRow(day) {
  const checkbox = document.querySelector(`.day-${day}`);
  const timesDiv = document.getElementById(`day-times-${day}`);
  const startInput = document.querySelector(`.day-start-${day}`);
  const endInput = document.querySelector(`.day-end-${day}`);

  if (checkbox.checked) {
    timesDiv.classList.remove('opacity-40');
    startInput.disabled = false;
    endInput.disabled = false;
  } else {
    timesDiv.classList.add('opacity-40');
    startInput.disabled = true;
    endInput.disabled = true;
  }
}

async function saveSchedule(doctorId) {
  const slotDuration = parseInt(document.getElementById('slotDuration').value);
  const slots = [];

  for (let day = 0; day < 7; day++) {
    const checkbox = document.querySelector(`.day-${day}`);
    if (checkbox && checkbox.checked) {
      const start = document.querySelector(`.day-start-${day}`).value;
      const end = document.querySelector(`.day-end-${day}`).value;
      if (start && end && start < end) {
        slots.push({ day, start, end });
      }
    }
  }

  await SahatnaDB.updateSchedule(doctorId, slots, slotDuration);
  showToast('تم حفظ دوام الطبيب بنجاح', 'success');
}

// ---- Reminders -----------------------------------------------------------
async function renderReminders() {
  const db = await SahatnaDB.load();
  const doctorIds = db.doctors.filter((d) => d.clinicId === currentClinic.id).map((d) => d.id);
  const reminders = db.reminders.filter((r) => {
    const booking = db.bookings.find((b) => b.id === r.bookingId);
    return booking && doctorIds.includes(booking.doctorId);
  });

  const today = new Date().toISOString().slice(0, 10);
  const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  reminders.sort((a, b) => {
    if (a.sent !== b.sent) return a.sent ? 1 : -1;
    const aRank = a.date === today ? 0 : a.date === tomorrow ? 1 : 2;
    const bRank = b.date === today ? 0 : b.date === tomorrow ? 1 : 2;
    if (aRank !== bRank) return aRank - bRank;
    if (a.date !== b.date) return a.date < b.date ? -1 : 1;
    if (a.time !== b.time) return a.time < b.time ? -1 : 1;
    return 0;
  });

  const list = document.getElementById('remindersList');

  if (reminders.length === 0) {
    list.innerHTML = `<div class="empty-state"><div class="empty-state-icon">📱</div><p class="text-gray-400">لا توجد تذكيرات حالياً</p></div>`;
    await updateRemindersBadge();
    return;
  }

  list.innerHTML = reminders
    .map((r) => {
      const dayName = SahatnaDB.getDayName(new Date(r.date + 'T00:00:00').getDay());
      const timeParts = r.time.split(':').map(Number);
      const isToday = r.date === today;
      const isTomorrow = r.date === tomorrow;
      const dateLabel = isToday ? 'اليوم' : isTomorrow ? 'غداً' : dayName;
      return `
        <div class="border border-gray-200 rounded-xl p-4 bg-white flex items-center justify-between ${isToday ? 'border-r-4 border-r-primary' : ''}">
          <div>
            <div class="flex items-center gap-2 mb-1">
              <span class="font-bold text-gray-800">${r.patientName}</span>
              ${r.sent ? '<span class="badge badge-success">تم الإرسال</span>' : '<span class="badge badge-warning">بانتظار الإرسال</span>'}
              ${isToday ? '<span class="badge badge-primary">اليوم</span>' : ''}
              ${isTomorrow ? '<span class="badge badge-info">غداً</span>' : ''}
            </div>
            <p class="text-sm text-gray-500">📞 ${r.patientPhone}</p>
            <p class="text-sm text-gray-500">📅 ${dateLabel} ${r.date} • ⏰ ${SahatnaDB.formatTime(timeParts[0], timeParts[1])}</p>
            <p class="text-xs text-gray-400 mt-1">👨‍⚕️ ${r.doctorName} - ${r.clinicName}</p>
          </div>
          ${!r.sent ? `<button onclick="sendReminder('${r.id}')" class="btn-primary text-sm">📤 إرسال</button>` : ''}
        </div>
      `;
    })
    .join('');

  await updateRemindersBadge();
}

async function sendReminder(reminderId) {
  const db = await SahatnaDB.load();
  const reminder = db.reminders.find((r) => r.id === reminderId);
  if (!reminder) {
    showToast('التذكير غير موجود', 'error');
    return;
  }
  WhatsAppReminder.send(reminder);
  await SahatnaDB.markReminderSent(reminderId);
  await renderReminders();
  showToast('تم فتح واتساب لإرسال التذكير', 'success');
}

async function sendAllReminders() {
  const db = await SahatnaDB.load();
  const doctorIds = db.doctors.filter((d) => d.clinicId === currentClinic.id).map((d) => d.id);
  const pending = db.reminders.filter((r) => {
    if (r.sent) return false;
    const booking = db.bookings.find((b) => b.id === r.bookingId);
    return booking && doctorIds.includes(booking.doctorId);
  });

  if (pending.length === 0) {
    showToast('لا توجد تذكيرات بانتظار الإرسال', 'info');
    return;
  }

  pending.forEach((r, i) => {
    setTimeout(async () => {
      WhatsAppReminder.send(r);
      await SahatnaDB.markReminderSent(r.id);
      await renderReminders();
    }, i * 2000);
  });
  showToast(`جارٍ فتح واتساب لإرسال ${pending.length} تذكير...`, 'info');
}

async function updateRemindersBadge() {
  const db = await SahatnaDB.load();
  const doctorIds = db.doctors.filter((d) => d.clinicId === currentClinic.id).map((d) => d.id);
  const unsentCount = db.reminders.filter((r) => {
    if (r.sent) return false;
    const booking = db.bookings.find((b) => b.id === r.bookingId);
    return booking && doctorIds.includes(booking.doctorId);
  }).length;

  const badge = document.getElementById('remindersBadge');
  if (!badge) return;
  if (unsentCount > 0) {
    badge.textContent = unsentCount;
    badge.classList.remove('hidden');
  } else {
    badge.classList.add('hidden');
  }
}

// ---- Initialize ----------------------------------------------------------
document.addEventListener('DOMContentLoaded', checkClinicSession);