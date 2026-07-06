/**
 * صحتنا - Patient App Logic
 * Handles search, filtering, doctor profiles, and booking flow.
 */

// ---- State ---------------------------------------------------------------
let currentSelectedDate = null;
let currentSelectedTime = null;
let currentSelectedService = 'clinic';
let currentDoctorId = null;

// ---- Utilities -----------------------------------------------------------
function formatPrice(price) {
  return new Intl.NumberFormat('ar-IQ').format(price) + ' د.ع';
}

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

function renderStars(rating) {
  const full = Math.floor(rating);
  const half = rating % 1 >= 0.5;
  let html = '';
  for (let i = 0; i < 5; i++) {
    if (i < full) {
      html += '<span class="star-filled">★</span>';
    } else if (i === full && half) {
      html += '<span class="star-filled">★</span>';
    } else {
      html += '<span class="star-empty">★</span>';
    }
  }
  return `<span class="star-rating">${html}</span>`;
}

function getServiceLabel(service) {
  const labels = {
    clinic: 'زيارة عيادة',
    video: 'استشارة فيديو',
    home: 'زيارة منزلية',
  };
  return labels[service] || service;
}

function getServiceIcon(service) {
  const icons = {
    clinic: '🏥',
    video: '📹',
    home: '🏠',
  };
  return icons[service] || '🏥';
}

// ---- Initialization ------------------------------------------------------
function initApp() {
  populateCityDropdown();
  populateSpecialtyDropdown();
  renderSpecialtiesGrid();
  renderStats();
  renderDoctors();
  setupEventListeners();
  setupMobileMenu();
}

function populateCityDropdown() {
  const db = SahatnaDB.load();
  const select = document.getElementById('searchCity');
  db.cities.forEach((city) => {
    const opt = document.createElement('option');
    opt.value = city.id;
    opt.textContent = city.name;
    select.appendChild(opt);
  });
}

function populateSpecialtyDropdown() {
  const db = SahatnaDB.load();
  const select = document.getElementById('searchSpecialty');
  db.specialties.forEach((sp) => {
    const opt = document.createElement('option');
    opt.value = sp.id;
    opt.textContent = sp.name;
    select.appendChild(opt);
  });
}

function renderSpecialtiesGrid() {
  const db = SahatnaDB.load();
  const grid = document.getElementById('specialtiesGrid');
  grid.innerHTML = db.specialties
    .map(
      (sp) => `
    <button onclick="filterBySpecialty('${sp.id}')" class="bg-gray-50 hover:bg-primary-lighter border border-gray-200 hover:border-primary rounded-2xl p-4 text-center transition group">
      <div class="text-3xl mb-2 group-hover:scale-110 transition">${sp.icon}</div>
      <div class="text-sm font-semibold text-gray-700 group-hover:text-primary">${sp.name}</div>
    </button>
  `
    )
    .join('');
}

function renderStats() {
  const db = SahatnaDB.load();
  document.getElementById('statDoctors').textContent = db.doctors.length;
  document.getElementById('statClinics').textContent =
    db.clinics.filter((c) => c.status === 'approved').length;
  document.getElementById('statSpecialties').textContent = db.specialties.length;
}

// ---- Search & Filter -----------------------------------------------------
function getFilteredDoctors() {
  const db = SahatnaDB.load();
  const nameQuery = document.getElementById('searchName').value.trim().toLowerCase();
  const cityId = document.getElementById('searchCity').value;
  const specialtyId = document.getElementById('searchSpecialty').value;
  const filterToday = document.getElementById('filterToday').checked;
  const filterVideo = document.getElementById('filterVideo').checked;
  const filterHome = document.getElementById('filterHome').checked;
  const filterFemale = document.getElementById('filterFemale').checked;
  const sortBy = document.getElementById('sortBy').value;

  let doctors = db.doctors.filter((d) => {
    // Only show doctors from approved clinics
    const clinic = db.clinics.find((c) => c.id === d.clinicId);
    if (!clinic || clinic.status !== 'approved') return false;

    // Name search
    if (nameQuery) {
      const sp = db.specialties.find((s) => s.id === d.specialtyId);
      const matches =
        d.name.toLowerCase().includes(nameQuery) ||
        d.nameEn.toLowerCase().includes(nameQuery) ||
        (sp && sp.name.toLowerCase().includes(nameQuery));
      if (!matches) return false;
    }

    // City filter
    if (cityId && clinic.cityId !== cityId) return false;

    // Specialty filter
    if (specialtyId && d.specialtyId !== specialtyId) return false;

    // Service filters
    if (filterVideo && !d.services.includes('video')) return false;
    if (filterHome && !d.services.includes('home')) return false;

    // Gender filter
    if (filterFemale && d.gender !== 'female') return false;

    // Today filter
    if (filterToday) {
      const today = new Date().toISOString().slice(0, 10);
      const slots = SahatnaDB.getAvailableSlots(d.id, today);
      if (slots.length === 0) return false;
    }

    return true;
  });

  // Sort
  doctors.sort((a, b) => {
    switch (sortBy) {
      case 'price-low':
        return a.price - b.price;
      case 'price-high':
        return b.price - a.price;
      case 'experience':
        return b.experienceYears - a.experienceYears;
      case 'rating':
      default:
        return b.rating - a.rating;
    }
  });

  // Featured doctors first
  doctors.sort((a, b) => (b.featured ? 1 : 0) - (a.featured ? 1 : 0));

  return doctors;
}

function renderDoctors() {
  const doctors = getFilteredDoctors();
  const list = document.getElementById('doctorsList');
  const countEl = document.getElementById('resultsCount');

  countEl.textContent = `(${doctors.length} طبيب)`;

  if (doctors.length === 0) {
    list.innerHTML = `
      <div class="col-span-full empty-state">
        <div class="empty-state-icon">🔍</div>
        <h4 class="text-lg font-bold text-gray-500 mb-2">لا توجد نتائج مطابقة</h4>
        <p class="text-gray-400">جرّب تعديل معايير البحث أو مسح التصفية</p>
      </div>
    `;
    return;
  }

  list.innerHTML = doctors
    .map((doctor) => {
      const specialty = SahatnaDB.getSpecialty(doctor.specialtyId);
      const clinic = SahatnaDB.getClinic(doctor.clinicId);
      const city = clinic ? SahatnaDB.getCity(clinic.cityId) : null;
      const today = new Date().toISOString().slice(0, 10);
      const todaySlots = SahatnaDB.getAvailableSlots(doctor.id, today);

      return `
      <div class="doctor-card bg-white rounded-2xl p-4 cursor-pointer animate-fade-in" onclick="openDoctorModal('${doctor.id}')">
        <div class="flex gap-4">
          <!-- Photo -->
          <div class="relative flex-shrink-0">
            <img src="${doctor.photo}" alt="${doctor.name}" class="w-20 h-20 rounded-2xl object-cover" />
            ${doctor.verified ? '<div class="verified-badge absolute -bottom-1 -left-1" title="طبيب موثّق">✓</div>' : ''}
          </div>

          <!-- Info -->
          <div class="flex-1 min-w-0">
            <div class="flex items-start justify-between gap-2">
              <div>
                <h4 class="font-bold text-gray-800 truncate">${doctor.name}</h4>
                <p class="text-sm text-primary font-medium">${specialty ? specialty.name : ''}</p>
                <p class="text-xs text-gray-500 mt-1">
                  📍 ${clinic ? clinic.area : ''}، ${city ? city.name : ''}
                </p>
              </div>
              ${doctor.featured ? '<span class="badge badge-warning flex-shrink-0">⭐ مميز</span>' : ''}
            </div>

            <!-- Rating & Stats -->
            <div class="flex items-center gap-3 mt-2 text-sm">
              <span class="flex items-center gap-1">
                ${renderStars(doctor.rating)}
                <span class="font-bold text-gray-700">${doctor.rating}</span>
                <span class="text-gray-400 text-xs">(${doctor.reviewsCount})</span>
              </span>
              <span class="text-gray-300">|</span>
              <span class="text-gray-500 text-xs">خبرة ${doctor.experienceYears} سنة</span>
            </div>

            <!-- Services -->
            <div class="flex flex-wrap gap-1 mt-2">
              ${doctor.services.map((s) => `<span class="badge badge-primary text-xs">${getServiceIcon(s)} ${getServiceLabel(s)}</span>`).join('')}
            </div>

            <!-- Price & Availability -->
            <div class="flex items-center justify-between mt-3 pt-3 border-t border-gray-100">
              <div>
                <span class="text-xs text-gray-400">سعر الكشف</span>
                <div class="font-bold text-primary">${formatPrice(doctor.price)}</div>
              </div>
              <div class="text-left">
                ${todaySlots.length > 0
                  ? `<span class="badge badge-success">متاح اليوم (${todaySlots.length})</span>`
                  : `<span class="badge badge-info">احجز لاحقاً</span>`}
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
    })
    .join('');
}

function filterBySpecialty(specialtyId) {
  document.getElementById('searchSpecialty').value = specialtyId;
  renderDoctors();
  document.getElementById('search').scrollIntoView({ behavior: 'smooth' });
}

// ---- Doctor Profile Modal & Booking --------------------------------------
function openDoctorModal(doctorId) {
  currentDoctorId = doctorId;
  currentSelectedDate = null;
  currentSelectedTime = null;
  currentSelectedService = 'clinic';

  const doctor = SahatnaDB.getDoctor(doctorId);
  if (!doctor) return;

  const specialty = SahatnaDB.getSpecialty(doctor.specialtyId);
  const clinic = SahatnaDB.getClinic(doctor.clinicId);
  const city = clinic ? SahatnaDB.getCity(clinic.cityId) : null;
  const db = SahatnaDB.load();
  const reviews = db.reviews.filter((r) => r.doctorId === doctorId);
  const days = SahatnaDB.getAvailableDays(doctorId, 14);

  const modal = document.getElementById('doctorModal');
  modal.classList.remove('hidden');
  modal.innerHTML = `
    <div class="modal-overlay" onclick="if(event.target===this) closeDoctorModal()">
      <div class="modal-content max-w-2xl">
        <!-- Header -->
        <div class="bg-gradient-to-br from-primary to-primary-dark text-white p-6 rounded-t-2xl relative">
          <button onclick="closeDoctorModal()" class="absolute top-4 left-4 text-white/80 hover:text-white text-2xl">✕</button>
          <div class="flex gap-4">
            <img src="${doctor.photo}" alt="${doctor.name}" class="w-24 h-24 rounded-2xl border-4 border-white/30 object-cover" />
            <div class="flex-1">
              <div class="flex items-center gap-2">
                <h3 class="text-xl font-bold">${doctor.name}</h3>
                ${doctor.verified ? '<span class="bg-white text-primary rounded-full w-6 h-6 flex items-center justify-center text-sm font-bold">✓</span>' : ''}
              </div>
              <p class="text-teal-100">${specialty ? specialty.name : ''}</p>
              <p class="text-sm text-teal-200 mt-1">📍 ${clinic ? clinic.name : ''} - ${clinic ? clinic.area : ''}، ${city ? city.name : ''}</p>
              <div class="flex items-center gap-3 mt-2">
                <span class="flex items-center gap-1">
                  ${renderStars(doctor.rating)}
                  <span class="font-bold">${doctor.rating}</span>
                  <span class="text-teal-200 text-sm">(${doctor.reviewsCount} تقييم)</span>
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Body -->
        <div class="p-6 max-h-[60vh] overflow-y-auto">
          <!-- Service Selection -->
          <h4 class="font-bold text-gray-800 mb-2">نوع الخدمة</h4>
          <div class="grid grid-cols-3 gap-2 mb-4">
            ${doctor.services
              .map(
                (s) => `
              <button onclick="selectService('${s}')" id="service-btn-${s}"
                class="service-btn p-3 border-2 border-gray-200 rounded-xl text-center transition hover:border-primary ${s === 'clinic' ? 'selected' : ''}">
                <div class="text-2xl mb-1">${getServiceIcon(s)}</div>
                <div class="text-xs font-semibold">${getServiceLabel(s)}</div>
              </button>
            `
              )
              .join('')}
          </div>

          <!-- About -->
          <div class="mb-4">
            <h4 class="font-bold text-gray-800 mb-2">نبذة عن الطبيب</h4>
            <p class="text-gray-600 text-sm leading-relaxed">${doctor.bio}</p>
          </div>

          <!-- Qualifications -->
          <div class="mb-4">
            <h4 class="font-bold text-gray-800 mb-2">المؤهلات</h4>
            <p class="text-gray-600 text-sm">🎓 ${doctor.qualifications}</p>
            <p class="text-gray-600 text-sm mt-1">⏱️ خبرة ${doctor.experienceYears} سنة</p>
            <p class="text-gray-600 text-sm mt-1">🗣️ اللغات: ${doctor.languages.join('، ')}</p>
          </div>

          <!-- Clinic Info -->
          ${clinic ? `
          <div class="mb-4 bg-gray-50 rounded-xl p-4">
            <h4 class="font-bold text-gray-800 mb-2">موقع العيادة</h4>
            <p class="text-gray-600 text-sm">🏥 ${clinic.name}</p>
            <p class="text-gray-500 text-sm mt-1">📍 ${clinic.address}</p>
            <p class="text-gray-500 text-sm mt-1">📞 ${clinic.phone}</p>
          </div>
          ` : ''}

          <!-- Date Selection -->
          <h4 class="font-bold text-gray-800 mb-2">اختر اليوم</h4>
          <div class="flex gap-2 overflow-x-auto pb-2 scrollbar-hide mb-4">
            ${days
              .map(
                (day) => `
              <button onclick="selectDate('${day.date}')"
                id="day-btn-${day.date}"
                class="day-btn flex-shrink-0 ${day.slotsCount === 0 ? 'disabled' : ''}">
                <div class="text-xs text-gray-500">${day.dayName}</div>
                <div class="text-lg font-bold">${day.dayNumber}</div>
                <div class="text-xs text-gray-500">${day.monthName}</div>
                <div class="text-xs mt-1 ${day.slotsCount > 0 ? 'text-primary font-bold' : 'text-gray-400'}">
                  ${day.slotsCount > 0 ? day.slotsCount + ' موعد' : 'لا يوجد'}
                </div>
              </button>
            `
              )
              .join('')}
          </div>

          <!-- Time Slots -->
          <div id="timeSlotsContainer" class="mb-4">
            <p class="text-gray-400 text-sm text-center py-8">اختر يوماً لعرض المواعيد المتاحة</p>
          </div>

          <!-- Reviews -->
          ${reviews.length > 0 ? `
          <div class="mb-4">
            <h4 class="font-bold text-gray-800 mb-2">التقييمات والمراجعات</h4>
            <div class="space-y-3">
              ${reviews
                .map(
                  (r) => `
                <div class="bg-gray-50 rounded-xl p-3">
                  <div class="flex items-center justify-between mb-1">
                    <span class="font-semibold text-sm text-gray-700">${r.patientName}</span>
                    <span class="text-xs text-gray-400">${r.date}</span>
                  </div>
                  <div class="flex items-center gap-2 mb-1">
                    ${renderStars(r.rating)}
                    ${r.verified ? '<span class="badge badge-success text-xs">زيارة موثّقة</span>' : ''}
                  </div>
                  <p class="text-gray-600 text-sm">${r.comment}</p>
                </div>
              `
                )
                .join('')}
            </div>
          </div>
          ` : ''}
        </div>

        <!-- Footer with price -->
        <div class="border-t border-gray-200 p-4 bg-gray-50 rounded-b-2xl">
          <div class="flex items-center justify-between">
            <div>
              <span class="text-xs text-gray-400">سعر الكشف</span>
              <div class="text-xl font-bold text-primary">${formatPrice(doctor.price)}</div>
            </div>
            <button id="bookBtn" onclick="openBookingForm()" disabled
              class="btn-primary opacity-50 cursor-not-allowed">
              احجز الموعد
            </button>
          </div>
        </div>
      </div>
    </div>
  `;

  // Auto-select first available day
  const firstAvailable = days.find((d) => d.slotsCount > 0);
  if (firstAvailable) {
    selectDate(firstAvailable.date);
  }
}

function closeDoctorModal() {
  document.getElementById('doctorModal').classList.add('hidden');
  document.getElementById('doctorModal').innerHTML = '';
  currentDoctorId = null;
  currentSelectedDate = null;
  currentSelectedTime = null;
}

function selectService(service) {
  currentSelectedService = service;
  // Update UI
  document.querySelectorAll('.service-btn').forEach((btn) => {
    btn.classList.remove('selected');
    btn.style.background = '';
    btn.style.borderColor = '';
    btn.style.color = '';
  });
  const btn = document.getElementById('service-btn-' + service);
  if (btn) {
    btn.classList.add('selected');
    btn.style.background = 'var(--primary)';
    btn.style.borderColor = 'var(--primary)';
    btn.style.color = 'white';
  }
}

function selectDate(dateStr) {
  if (!currentDoctorId) return;
  currentSelectedDate = dateStr;
  currentSelectedTime = null;

  // Update day button UI
  document.querySelectorAll('.day-btn').forEach((btn) => {
    btn.classList.remove('selected');
  });
  const dayBtn = document.getElementById('day-btn-' + dateStr);
  if (dayBtn && !dayBtn.classList.contains('disabled')) {
    dayBtn.classList.add('selected');
  }

  // Render time slots
  const slots = SahatnaDB.getAvailableSlots(currentDoctorId, dateStr);
  const container = document.getElementById('timeSlotsContainer');

  if (slots.length === 0) {
    container.innerHTML = '<p class="text-gray-400 text-sm text-center py-4">لا توجد مواعيد متاحة في هذا اليوم</p>';
    updateBookButton();
    return;
  }

  container.innerHTML = `
    <h4 class="font-bold text-gray-800 mb-2">المواعيد المتاحة</h4>
    <div class="grid grid-cols-3 sm:grid-cols-4 gap-2">
      ${slots
        .map(
          (slot) => `
        <button onclick="selectTime('${slot.time}')"
          id="slot-${slot.time}"
          class="time-slot">
          ${slot.label}
        </button>
      `
        )
        .join('')}
    </div>
  `;
  updateBookButton();
}

function selectTime(time) {
  currentSelectedTime = time;
  document.querySelectorAll('.time-slot').forEach((btn) => {
    btn.classList.remove('selected');
  });
  const btn = document.getElementById('slot-' + time);
  if (btn) btn.classList.add('selected');
  updateBookButton();
}

function updateBookButton() {
  const btn = document.getElementById('bookBtn');
  if (!btn) return;
  if (currentSelectedDate && currentSelectedTime) {
    btn.disabled = false;
    btn.classList.remove('opacity-50', 'cursor-not-allowed');
  } else {
    btn.disabled = true;
    btn.classList.add('opacity-50', 'cursor-not-allowed');
  }
}

// ---- Booking Form --------------------------------------------------------
function openBookingForm() {
  if (!currentSelectedDate || !currentSelectedTime || !currentDoctorId) return;

  const doctor = SahatnaDB.getDoctor(currentDoctorId);
  const clinic = SahatnaDB.getClinic(doctor.clinicId);
  const dayName = SahatnaDB.getDayName(new Date(currentSelectedDate + 'T00:00:00').getDay());

  const modal = document.getElementById('doctorModal');
  modal.innerHTML = `
    <div class="modal-overlay" onclick="if(event.target===this) closeDoctorModal()">
      <div class="modal-content">
        <!-- Header -->
        <div class="bg-primary text-white p-5 rounded-t-2xl">
          <h3 class="text-lg font-bold">تأكيد الحجز</h3>
          <p class="text-teal-100 text-sm mt-1">أدخل بياناتك لتأكيد الموعد</p>
        </div>

        <!-- Body -->
        <div class="p-6">
          <!-- Booking Summary -->
          <div class="bg-primary-lighter rounded-xl p-4 mb-4">
            <div class="flex items-center gap-3 mb-3">
              <img src="${doctor.photo}" class="w-14 h-14 rounded-xl object-cover" />
              <div>
                <h4 class="font-bold text-gray-800">${doctor.name}</h4>
                <p class="text-sm text-gray-600">${SahatnaDB.getSpecialty(doctor.specialtyId).name}</p>
              </div>
            </div>
            <div class="grid grid-cols-2 gap-2 text-sm">
              <div class="flex items-center gap-2">
                <span class="text-gray-400">📅 التاريخ:</span>
                <span class="font-semibold">${dayName} ${currentSelectedDate}</span>
              </div>
              <div class="flex items-center gap-2">
                <span class="text-gray-400">⏰ الوقت:</span>
                <span class="font-semibold">${SahatnaDB.formatTime(
                  parseInt(currentSelectedTime.split(':')[0]),
                  parseInt(currentSelectedTime.split(':')[1])
                )}</span>
              </div>
              <div class="flex items-center gap-2">
                <span class="text-gray-400">🏥 الخدمة:</span>
                <span class="font-semibold">${getServiceLabel(currentSelectedService)}</span>
              </div>
              <div class="flex items-center gap-2">
                <span class="text-gray-400">💰 السعر:</span>
                <span class="font-semibold text-primary">${formatPrice(doctor.price)}</span>
              </div>
            </div>
          </div>

          <!-- Patient Info Form -->
          <form id="bookingForm" onsubmit="confirmBooking(event)">
            <div class="space-y-3">
              <div>
                <label class="block text-sm font-semibold text-gray-600 mb-1">الاسم الكامل *</label>
                <input type="text" id="patientName" required placeholder="مثال: أحمد محمد علي" class="form-input" />
              </div>
              <div>
                <label class="block text-sm font-semibold text-gray-600 mb-1">رقم الهاتف *</label>
                <input type="tel" id="patientPhone" required placeholder="07XX XXX XXXX" pattern="07[0-9]{9}" class="form-input" />
                <p class="text-xs text-gray-400 mt-1">سيتم إرسال تأكيد الحجز والتذكير على هذا الرقم</p>
              </div>
              <div>
                <label class="block text-sm font-semibold text-gray-600 mb-1">العمر</label>
                <input type="number" id="patientAge" min="1" max="120" placeholder="مثال: 35" class="form-input" />
              </div>
              <div>
                <label class="block text-sm font-semibold text-gray-600 mb-1">ملاحظات (اختياري)</label>
                <textarea id="patientNotes" rows="2" placeholder="أعراض أو معلومات تريد إخبار الطبيب عنها" class="form-input"></textarea>
              </div>

              <!-- Payment Method -->
              <div>
                <label class="block text-sm font-semibold text-gray-600 mb-2">طريقة الدفع</label>
                <div class="grid grid-cols-1 gap-2">
                  <label class="flex items-center gap-3 p-3 border-2 border-primary rounded-xl bg-primary-lighter cursor-pointer">
                    <input type="radio" name="payment" value="clinic" checked class="text-primary" />
                    <div>
                      <div class="font-semibold text-sm">💰 ادفع بالعيادة</div>
                      <div class="text-xs text-gray-500">ادفع نقداً عند الحضور للموعد</div>
                    </div>
                  </label>
                </div>
              </div>
            </div>

            <!-- Actions -->
            <div class="flex gap-3 mt-6">
              <button type="button" onclick="openDoctorModal('${currentDoctorId}')" class="btn-secondary flex-1">
                رجوع
              </button>
              <button type="submit" class="btn-primary flex-1">
                تأكيد الحجز
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  `;
}

function confirmBooking(event) {
  event.preventDefault();

  const patientName = document.getElementById('patientName').value.trim();
  const patientPhone = document.getElementById('patientPhone').value.trim();
  const patientAge = document.getElementById('patientAge').value;
  const patientNotes = document.getElementById('patientNotes').value.trim();

  if (!patientName || !patientPhone) {
    showToast('يرجى ملء جميع الحقول المطلوبة', 'error');
    return;
  }

  const doctor = SahatnaDB.getDoctor(currentDoctorId);

  const booking = SahatnaDB.createBooking({
    doctorId: currentDoctorId,
    clinicId: doctor.clinicId,
    patientName,
    patientPhone,
    patientAge: patientAge || null,
    patientNotes,
    date: currentSelectedDate,
    time: currentSelectedTime,
    service: currentSelectedService,
    price: doctor.price,
  });

  showBookingSuccess(booking, doctor);
}

function showBookingSuccess(booking, doctor) {
  const clinic = SahatnaDB.getClinic(doctor.clinicId);
  const dayName = SahatnaDB.getDayName(new Date(booking.date + 'T00:00:00').getDay());
  const timeParts = booking.time.split(':').map(Number);

  const modal = document.getElementById('successModal');
  modal.classList.remove('hidden');
  modal.innerHTML = `
    <div class="modal-overlay" onclick="if(event.target===this) closeSuccessModal()">
      <div class="modal-content text-center">
        <div class="p-8">
          <!-- Success Icon -->
          <div class="w-20 h-20 bg-success-light rounded-full flex items-center justify-center mx-auto mb-4 animate-scale-in">
            <svg class="w-12 h-12 text-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7" />
            </svg>
          </div>

          <h3 class="text-2xl font-bold text-gray-800 mb-2">تم تأكيد حجزك بنجاح! 🎉</h3>
          <p class="text-gray-500 mb-6">سيصلك تذكير برسالة نصية قبل الموعد</p>

          <!-- Booking Details -->
          <div class="bg-gray-50 rounded-xl p-4 text-right mb-6">
            <div class="flex items-center gap-3 mb-3 pb-3 border-b border-gray-200">
              <img src="${doctor.photo}" class="w-12 h-12 rounded-xl object-cover" />
              <div>
                <h4 class="font-bold text-gray-800">${doctor.name}</h4>
                <p class="text-sm text-gray-500">${SahatnaDB.getSpecialty(doctor.specialtyId).name}</p>
              </div>
            </div>
            <div class="space-y-2 text-sm">
              <div class="flex justify-between">
                <span class="text-gray-400">رقم الحجز:</span>
                <span class="font-bold text-primary">#${booking.id}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-400">التاريخ:</span>
                <span class="font-semibold">${dayName} ${booking.date}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-400">الوقت:</span>
                <span class="font-semibold">${SahatnaDB.formatTime(timeParts[0], timeParts[1])}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-400">العيادة:</span>
                <span class="font-semibold">${clinic.name}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-400">العنوان:</span>
                <span class="font-semibold text-xs">${clinic.address}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-400">طريقة الدفع:</span>
                <span class="font-semibold">ادفع بالعيادة</span>
              </div>
              <div class="flex justify-between pt-2 border-t border-gray-200">
                <span class="text-gray-400">السعر:</span>
                <span class="font-bold text-primary">${formatPrice(doctor.price)}</span>
              </div>
            </div>
          </div>

          <!-- Reminder note -->
          <div class="bg-info-light rounded-xl p-3 mb-6 text-sm text-info flex items-center gap-2 justify-center">
            <span>📱</span>
            <span>سيصلك تذكير على الرقم ${booking.patientPhone} قبل الموعد</span>
          </div>

          <button onclick="closeSuccessModal()" class="btn-primary w-full">
            تم
          </button>
        </div>
      </div>
    </div>
  `;

  closeDoctorModal();
  showToast('تم تأكيد الحجز بنجاح!', 'success');
}

function closeSuccessModal() {
  document.getElementById('successModal').classList.add('hidden');
  document.getElementById('successModal').innerHTML = '';
}

// ---- Clinic Registration Modal -------------------------------------------
function openRegisterModal() {
  const db = SahatnaDB.load();
  const modal = document.getElementById('registerModal');
  modal.classList.remove('hidden');
  modal.innerHTML = `
    <div class="modal-overlay" onclick="if(event.target===this) closeRegisterModal()">
      <div class="modal-content">
        <div class="bg-primary text-white p-5 rounded-t-2xl flex items-center justify-between">
          <div>
            <h3 class="text-lg font-bold">سجّل عيادتك معنا</h3>
            <p class="text-teal-100 text-sm mt-1">انضم لشبكة صحتنا ووسّع قاعدة مرضاك</p>
          </div>
          <button onclick="closeRegisterModal()" class="text-white/80 hover:text-white text-2xl">✕</button>
        </div>

        <div class="p-6">
          <form onsubmit="submitClinicRegistration(event)">
            <div class="space-y-3">
              <div>
                <label class="block text-sm font-semibold text-gray-600 mb-1">اسم العيادة/المركز *</label>
                <input type="text" id="regClinicName" required placeholder="مثال: مركز الشفاء الطبي" class="form-input" />
              </div>
              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="block text-sm font-semibold text-gray-600 mb-1">المدينة *</label>
                  <select id="regCity" required class="form-input">
                    <option value="">اختر المدينة</option>
                    ${db.cities.map((c) => `<option value="${c.id}">${c.name}</option>`).join('')}
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-semibold text-gray-600 mb-1">المنطقة *</label>
                  <input type="text" id="regArea" required placeholder="مثال: الكرادة" class="form-input" />
                </div>
              </div>
              <div>
                <label class="block text-sm font-semibold text-gray-600 mb-1">العنوان التفصيلي *</label>
                <input type="text" id="regAddress" required placeholder="الشارع، أقرب نقطة دالة" class="form-input" />
              </div>
              <div>
                <label class="block text-sm font-semibold text-gray-600 mb-1">رقم الهاتف *</label>
                <input type="tel" id="regPhone" required placeholder="07XX XXX XXXX" class="form-input" />
              </div>
              <div class="bg-info-light rounded-xl p-3 text-sm text-info">
                ℹ️ سيتم مراجعة طلبك من قبل فريق صحتنا والموافقة عليه خلال 48 ساعة. سنتواصل معك على الرقم المُدخل.
              </div>
            </div>
            <button type="submit" class="btn-primary w-full mt-6">إرسال طلب التسجيل</button>
          </form>
        </div>
      </div>
    </div>
  `;
}

function closeRegisterModal() {
  document.getElementById('registerModal').classList.add('hidden');
  document.getElementById('registerModal').innerHTML = '';
}

function submitClinicRegistration(event) {
  event.preventDefault();
  const name = document.getElementById('regClinicName').value.trim();
  const cityId = document.getElementById('regCity').value;
  const area = document.getElementById('regArea').value.trim();
  const address = document.getElementById('regAddress').value.trim();
  const phone = document.getElementById('regPhone').value.trim();

  if (!name || !cityId || !area || !address || !phone) {
    showToast('يرجى ملء جميع الحقول', 'error');
    return;
  }

  SahatnaDB.addClinic({ name, cityId, area, address, phone, lat: 0, lng: 0 });
  closeRegisterModal();
  showToast('تم إرسال طلب التسجيل بنجاح! سنتواصل معك قريباً.', 'success');
}

// ---- Event Listeners -----------------------------------------------------
function setupEventListeners() {
  // Search inputs
  document.getElementById('searchName').addEventListener('input', renderDoctors);
  document.getElementById('searchCity').addEventListener('change', renderDoctors);
  document.getElementById('searchSpecialty').addEventListener('change', renderDoctors);
  document.getElementById('sortBy').addEventListener('change', renderDoctors);

  // Filters
  document.getElementById('filterToday').addEventListener('change', renderDoctors);
  document.getElementById('filterVideo').addEventListener('change', renderDoctors);
  document.getElementById('filterHome').addEventListener('change', renderDoctors);
  document.getElementById('filterFemale').addEventListener('change', renderDoctors);

  // Clear filters
  document.getElementById('clearFilters').addEventListener('click', () => {
    document.getElementById('searchName').value = '';
    document.getElementById('searchCity').value = '';
    document.getElementById('searchSpecialty').value = '';
    document.getElementById('filterToday').checked = false;
    document.getElementById('filterVideo').checked = false;
    document.getElementById('filterHome').checked = false;
    document.getElementById('filterFemale').checked = false;
    renderDoctors();
  });

  // ESC to close modals
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      closeDoctorModal();
      closeSuccessModal();
      closeRegisterModal();
    }
  });
}

function setupMobileMenu() {
  const btn = document.getElementById('mobileMenuBtn');
  const menu = document.getElementById('mobileMenu');
  btn.addEventListener('click', () => {
    menu.classList.toggle('hidden');
  });
  // Close menu when a link is clicked
  menu.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => menu.classList.add('hidden'));
  });
}

// ---- Initialize on load --------------------------------------------------
document.addEventListener('DOMContentLoaded', initApp);