/**
 * صحتنا - Sahatna Data Layer (Unified: Supabase + localStorage)
 *
 * All methods are async (return Promises). When Supabase is configured
 * (SUPABASE_CONFIG.enabled = true), data is fetched from PostgreSQL.
 * Otherwise, it falls back to localStorage with seed data.
 *
 * The public API is identical in both modes, so app.js / clinic.js / admin.js
 * work without any mode-specific logic.
 */

const SahatnaDB = (function () {
  const STORAGE_KEY = 'sahatna_db_v1';
  const CACHE_TTL = 5000;
  let _sb = null;
  let _initPromise = null;
  let cache = null;
  let cacheTime = 0;

  const seed = {
    specialties: [
      { id: 'sp1', name: 'طب الأسرة', nameEn: 'Family Medicine', icon: '👨‍👩‍👧' },
      { id: 'sp2', name: 'الباطنية', nameEn: 'Internal Medicine', icon: '🩺' },
      { id: 'sp3', name: 'الأطفال', nameEn: 'Pediatrics', icon: '🧒' },
      { id: 'sp4', name: 'النسائية والتوليد', nameEn: 'Gynecology', icon: '🤰' },
      { id: 'sp5', name: 'الجلدية', nameEn: 'Dermatology', icon: '🧴' },
      { id: 'sp6', name: 'الأسنان', nameEn: 'Dentistry', icon: '🦷' },
      { id: 'sp7', name: 'العيون', nameEn: 'Ophthalmology', icon: '👁️' },
      { id: 'sp8', name: 'الأنف والأذن والحنجرة', nameEn: 'ENT', icon: '👂' },
      { id: 'sp9', name: 'العظام', nameEn: 'Orthopedics', icon: '🦴' },
      { id: 'sp10', name: 'الجراحة العامة', nameEn: 'General Surgery', icon: '🔪' },
      { id: 'sp11', name: 'المخ والأعصاب', nameEn: 'Neurology', icon: '🧠' },
      { id: 'sp12', name: 'النفسية', nameEn: 'Psychiatry', icon: '💭' },
    ],
    cities: [
      { id: 'c1', name: 'بغداد' }, { id: 'c2', name: 'البصرة' },
      { id: 'c3', name: 'الموصل' }, { id: 'c4', name: 'أربيل' },
      { id: 'c5', name: 'النجف' }, { id: 'c6', name: 'كربلاء' },
      { id: 'c7', name: 'كركوك' }, { id: 'c8', name: 'السليمانية' },
      { id: 'c9', name: 'الديوانية' }, { id: 'c10', name: 'العمارة' },
      { id: 'c11', name: 'الناصرية' }, { id: 'c12', name: 'الحلة' },
    ],
    clinics: [
      { id: 'cl1', name: 'مركز الشفاء الطبي', cityId: 'c1', area: 'الكرادة', address: 'شارع الكرادة داخل، قرب مجمع الكرادة', phone: '07701234567', lat: 33.3152, lng: 44.4360, status: 'approved', createdAt: '2025-01-15T08:00:00Z' },
      { id: 'cl2', name: 'عيادة النور للتخصصات', cityId: 'c1', area: 'المنصور', address: 'شارع الأميرات، المنصور', phone: '07801234567', lat: 33.3230, lng: 44.3850, status: 'approved', createdAt: '2025-02-01T08:00:00Z' },
      { id: 'cl3', name: 'مستشفى الحياة الخاص', cityId: 'c2', area: 'العشار', address: 'شارع الكورنيش، العشار', phone: '07901234567', lat: 30.5085, lng: 47.7804, status: 'approved', createdAt: '2025-02-10T08:00:00Z' },
      { id: 'cl4', name: 'مركز الرافدين الطبي', cityId: 'c5', area: 'المركز', address: 'شارع الكوفة، النجف', phone: '07712345678', lat: 32.0000, lng: 44.3333, status: 'pending', createdAt: '2025-07-01T08:00:00Z' },
    ],
    doctors: [
      { id: 'd1', name: 'د. أحمد الكاظمي', nameEn: 'Dr. Ahmed Al-Kadhimi', specialtyId: 'sp2', clinicId: 'cl1', photo: 'https://ui-avatars.com/api/?name=Ahmed+K&background=0d9488&color=fff&size=200', bio: 'استشاري باطنية مع خبرة 15 سنة في تشخيص وعلاج الأمراض المزمنة مثل السكري وضغط الدم.', qualifications: 'بورد عراقي في الباطنية - جامعة بغداد', experienceYears: 15, price: 30000, gender: 'male', languages: ['العربية', 'English'], rating: 4.8, reviewsCount: 124, services: ['clinic', 'video'], verified: true, featured: true },
      { id: 'd2', name: 'د. سارة العبيدي', nameEn: 'Dr. Sara Al-Obaidi', specialtyId: 'sp4', clinicId: 'cl1', photo: 'https://ui-avatars.com/api/?name=Sara+O&background=db2777&color=fff&size=200', bio: 'أخصائية نسائية وتوليد، متخصصة في متابعة الحمل والعناية بصحة المرأة.', qualifications: 'بورد عراقي في النسائية - جامعة بغداد', experienceYears: 10, price: 35000, gender: 'female', languages: ['العربية'], rating: 4.9, reviewsCount: 89, services: ['clinic', 'video', 'home'], verified: true, featured: true },
      { id: 'd3', name: 'د. محمد الجبوري', nameEn: 'Dr. Mohammed Al-Jubouri', specialtyId: 'sp3', clinicId: 'cl2', photo: 'https://ui-avatars.com/api/?name=Mohammed+J&background=2563eb&color=fff&size=200', bio: 'طبيب أطفال متخصص في رعاية حديثي الولادة والأمراض المعدية لدى الأطفال.', qualifications: 'بورد عراقي في الأطفال - جامعة الموصل', experienceYears: 12, price: 25000, gender: 'male', languages: ['العربية', 'English', 'كوردی'], rating: 4.7, reviewsCount: 156, services: ['clinic', 'video'], verified: true, featured: false },
      { id: 'd4', name: 'د. زينب الحسني', nameEn: 'Dr. Zainab Al-Hasnawi', specialtyId: 'sp5', clinicId: 'cl2', photo: 'https://ui-avatars.com/api/?name=Zainab+H&background=7c3aed&color=fff&size=200', bio: 'أخصائية جلدية، علاج حب الشباب، التصبغات، وإجراءات التجميل غير الجراحي.', qualifications: 'بورد عراقي في الجلدية - جامعة البصرة', experienceYears: 8, price: 40000, gender: 'female', languages: ['العربية'], rating: 4.6, reviewsCount: 67, services: ['clinic'], verified: true, featured: false },
      { id: 'd5', name: 'د. عمر التميمي', nameEn: 'Dr. Omar Al-Tamimi', specialtyId: 'sp6', clinicId: 'cl3', photo: 'https://ui-avatars.com/api/?name=Omar+T&background=0891b2&color=fff&size=200', bio: 'طبيب أسنان تقويم وزراعة، خبرة في علاج التشوهات وتركيب الأسنان.', qualifications: 'ماجستير في تقويم الأسنان - جامعة بغداد', experienceYears: 14, price: 20000, gender: 'male', languages: ['العربية', 'English'], rating: 4.5, reviewsCount: 203, services: ['clinic'], verified: true, featured: true },
      { id: 'd6', name: 'د. نور الساعدي', nameEn: 'Dr. Noor Al-Saadi', specialtyId: 'sp1', clinicId: 'cl3', photo: 'https://ui-avatars.com/api/?name=Noor+S&background=059669&color=fff&size=200', bio: 'طبيبة طب أسرة، متابعة الأمراض المزمنة والوقائية لكل أفراد العائلة.', qualifications: 'بورد عراقي في طب الأسرة', experienceYears: 7, price: 20000, gender: 'female', languages: ['العربية', 'English'], rating: 4.9, reviewsCount: 45, services: ['clinic', 'video', 'home'], verified: true, featured: false },
    ],
    schedules: [
      { doctorId: 'd1', slots: [{ day: 0, start: '17:00', end: '21:00' }, { day: 1, start: '17:00', end: '21:00' }, { day: 2, start: '17:00', end: '21:00' }, { day: 3, start: '17:00', end: '21:00' }, { day: 5, start: '10:00', end: '14:00' }], slotDuration: 30 },
      { doctorId: 'd2', slots: [{ day: 0, start: '16:00', end: '20:00' }, { day: 2, start: '16:00', end: '20:00' }, { day: 4, start: '16:00', end: '20:00' }, { day: 6, start: '11:00', end: '15:00' }], slotDuration: 30 },
      { doctorId: 'd3', slots: [{ day: 1, start: '10:00', end: '14:00' }, { day: 3, start: '10:00', end: '14:00' }, { day: 5, start: '10:00', end: '14:00' }, { day: 6, start: '10:00', end: '14:00' }], slotDuration: 20 },
      { doctorId: 'd4', slots: [{ day: 0, start: '11:00', end: '15:00' }, { day: 2, start: '11:00', end: '15:00' }, { day: 4, start: '11:00', end: '15:00' }], slotDuration: 30 },
      { doctorId: 'd5', slots: [{ day: 1, start: '09:00', end: '13:00' }, { day: 2, start: '09:00', end: '13:00' }, { day: 3, start: '09:00', end: '13:00' }, { day: 4, start: '09:00', end: '13:00' }, { day: 5, start: '09:00', end: '13:00' }], slotDuration: 30 },
      { doctorId: 'd6', slots: [{ day: 0, start: '12:00', end: '16:00' }, { day: 1, start: '12:00', end: '16:00' }, { day: 2, start: '12:00', end: '16:00' }, { day: 3, start: '12:00', end: '16:00' }, { day: 4, start: '12:00', end: '16:00' }], slotDuration: 20 },
    ],
    reviews: [
      { id: 'r1', doctorId: 'd1', patientName: 'علي حسين', rating: 5, comment: 'طبيب محترم وخبير، شخّص حالتي بدقة.', date: '2025-06-20', verified: true },
      { id: 'r2', doctorId: 'd1', patientName: 'فاطمة عبد الله', rating: 4, comment: 'استشارة جيدة لكن الانتظار كان طويل شوية.', date: '2025-06-18', verified: true },
      { id: 'r3', doctorId: 'd2', patientName: 'مريم أحمد', rating: 5, comment: 'د. سارة رائعة، متابعة الحمل معها مريحة جداً.', date: '2025-06-22', verified: true },
      { id: 'r4', doctorId: 'd3', patientName: 'كريم سعد', rating: 5, comment: 'تعامله مع الأطفال ممتاز، ابني ما خاف من الطبيب.', date: '2025-06-19', verified: true },
      { id: 'r5', doctorId: 'd5', patientName: 'حسن كاظم', rating: 4, comment: 'علاج الأسنان كان جيد والأسعار معقولة.', date: '2025-06-15', verified: true },
    ],
    bookings: [],
    clinicUsers: [
      { id: 'cu1', clinicId: 'cl1', username: 'cl1', password: '1234', name: 'مدير مركز الشفاء' },
      { id: 'cu2', clinicId: 'cl2', username: 'cl2', password: '1234', name: 'مدير عيادة النور' },
      { id: 'cu3', clinicId: 'cl3', username: 'cl3', password: '1234', name: 'مدير مستشفى الحياة' },
    ],
    adminUsers: [{ username: 'admin', password: 'admin123', name: 'مدير صحتنا' }],
    reminders: [],
    nextBookingId: 1,
    nextReminderId: 1,
  };

  async function ensureInit() {
    if (_initPromise) return _initPromise;
    _initPromise = (async () => {
      if (typeof SUPABASE_CONFIG !== 'undefined' && SUPABASE_CONFIG.enabled) {
        _sb = await initSupabase();
        if (_sb) console.log('✅ SahatnaDB: Using Supabase');
        else console.warn('⚠️ SahatnaDB: Supabase init failed, using localStorage');
      } else {
        console.log('🔄 SahatnaDB: Using localStorage (demo mode)');
      }
    })();
    return _initPromise;
  }

  function isSupabase() { return _sb !== null; }
  function isSupabaseConfigured() {
    return typeof SUPABASE_CONFIG !== 'undefined' && SUPABASE_CONFIG.enabled === true;
  }
  async function useSupabase() {
    await ensureInit();
    return isSupabase();
  }
  function invalidateCache() { cache = null; }

  function escapeHTML(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function safeImageURL(value) {
    try {
      const url = new URL(String(value || ''), window.location.href);
      if (url.protocol === 'https:' || url.protocol === 'http:') return escapeHTML(url.href);
    } catch (e) { /* invalid URL */ }
    return '';
  }

  function mapSpecialty(s) { return { id: s.id, name: s.name, nameEn: s.name_en, icon: s.icon }; }
  function mapCity(c) { return { id: c.id, name: c.name }; }
  function mapClinic(c) {
    return { id: c.id, name: c.name, cityId: c.city_id, area: c.area, address: c.address, phone: c.phone, lat: parseFloat(c.lat) || 0, lng: parseFloat(c.lng) || 0, status: c.status, createdAt: c.created_at };
  }
  function mapDoctor(d) {
    return { id: d.id, name: d.name, nameEn: d.name_en, specialtyId: d.specialty_id, clinicId: d.clinic_id, photo: d.photo, bio: d.bio, qualifications: d.qualifications, experienceYears: d.experience_years, price: d.price, gender: d.gender, languages: d.languages || ['العربية'], rating: parseFloat(d.rating) || 0, reviewsCount: d.reviews_count || 0, services: d.services || ['clinic'], verified: d.verified, featured: d.featured };
  }
  function mapBooking(b) {
    return { id: b.id, doctorId: b.doctor_id, clinicId: b.clinic_id, patientName: b.patient_name, patientPhone: b.patient_phone, patientAge: b.patient_age, patientNotes: b.patient_notes, date: b.date, time: b.time, service: b.service, price: b.price, status: b.status, paymentMethod: b.payment_method, paymentStatus: b.payment_status || 'clinic', reviewed: Boolean(b.reviewed), createdAt: b.created_at };
  }
  function mapReview(r) {
    return { id: r.id, doctorId: r.doctor_id, patientName: r.patient_name, patientPhone: r.patient_phone, rating: r.rating, comment: r.comment, date: r.created_at ? r.created_at.slice(0, 10) : '', verified: r.verified, appointmentId: r.appointment_id };
  }
  function mapReminder(r) {
    return { id: r.id, bookingId: r.appointment_id, patientName: r.patient_name, patientPhone: r.patient_phone, doctorName: r.doctor_name, clinicName: r.clinic_name, date: r.date, time: r.time, sent: r.sent, sentAt: r.sent_at, createdAt: r.created_at };
  }
  function groupSchedules(rows) {
    const grouped = {};
    rows.forEach((r) => {
      if (!grouped[r.doctor_id]) grouped[r.doctor_id] = { doctorId: r.doctor_id, slots: [], slotDuration: r.slot_duration || 30 };
      grouped[r.doctor_id].slots.push({ day: r.day, start: r.start_time, end: r.end_time });
    });
    return Object.values(grouped);
  }

  function loadLocal() {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) { saveLocal(seed); return JSON.parse(JSON.stringify(seed)); }
    try { return JSON.parse(raw); } catch (e) { saveLocal(seed); return JSON.parse(JSON.stringify(seed)); }
  }
  function saveLocal(db) { localStorage.setItem(STORAGE_KEY, JSON.stringify(db)); }
  function resetLocal() { localStorage.removeItem(STORAGE_KEY); return loadLocal(); }

  async function loadFromSupabase() {
    if (cache && Date.now() - cacheTime < CACHE_TTL) return cache;
    try {
      const { data: sessionData } = await _sb.auth.getSession();
      const isAuthenticated = Boolean(sessionData && sessionData.session);
      let isStaff = false;
      if (isAuthenticated) {
        const [adminRole, clinicRole] = await Promise.all([
          _sb.rpc('is_admin'),
          _sb.rpc('is_clinic_user'),
        ]);
        isStaff = (!adminRole.error && adminRole.data === true)
          || (!clinicRole.error && clinicRole.data === true);
      }

      // Patient data is never selected from a view. A guarded RPC explicitly
      // checks clinic/admin membership before decrypting medical notes.
      let appointments = [];
      if (isStaff) {
        const aptsRes = await _sb.rpc('get_clinic_appointments');
        if (!aptsRes.error) appointments = aptsRes.data || [];
      }

      // Anonymous visitors only receive the public-safe clinic projection.
      // Clinic/admin sessions can read their authorized rows from the table.
      const clinicsQuery = isStaff
        ? _sb.from('clinics').select('*')
        : _sb.from('public_clinics').select('*');

      const [specs, cits, clins, docs, scheds, revs, rems] = await Promise.all([
        _sb.from('specialties').select('*'), _sb.from('cities').select('*'),
        clinicsQuery, _sb.from('doctors').select('*'),
        _sb.from('schedules').select('*'), _sb.from('public_reviews').select('*'),
        _sb.from('reminders').select('*'),
      ]);
      cache = {
        specialties: (specs.data || []).map(mapSpecialty), cities: (cits.data || []).map(mapCity),
        clinics: (clins.data || []).map(mapClinic), doctors: (docs.data || []).filter((d) => d.active !== false).map(mapDoctor),
        schedules: groupSchedules(scheds.data || []), reviews: (revs.data || []).map(mapReview),
        bookings: appointments.map(mapBooking), reminders: (rems.data || []).map(mapReminder),
        clinicUsers: [], adminUsers: [],
      };
      cacheTime = Date.now();
      return cache;
    } catch (e) {
      console.error('Supabase load error:', e);
      if (!cache) { cache = { specialties: [], cities: [], clinics: [], doctors: [], schedules: [], reviews: [], bookings: [], reminders: [], clinicUsers: [], adminUsers: [] }; cacheTime = Date.now(); }
      return cache;
    }
  }

  async function load() { await ensureInit(); return isSupabase() ? await loadFromSupabase() : loadLocal(); }
  async function getSpecialty(id) { return (await load()).specialties.find((s) => s.id === id); }
  async function getCity(id) { return (await load()).cities.find((c) => c.id === id); }
  async function getClinic(id) { return (await load()).clinics.find((c) => c.id === id); }
  async function getDoctor(id) { return (await load()).doctors.find((d) => d.id === id); }
  async function getSchedule(doctorId) { return (await load()).schedules.find((s) => s.doctorId === doctorId); }

  function formatTime(h, m) { const p = h >= 12 ? 'م' : 'ص'; let h12 = h % 12; if (h12 === 0) h12 = 12; return `${h12}:${String(m).padStart(2, '0')} ${p}`; }
  function getDayName(day) { return ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'][day]; }
  function getMonthName(month) { return ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'][month]; }

  async function getAvailableSlots(doctorId, dateStr) {
    const db = await load();
    const schedule = db.schedules.find((s) => s.doctorId === doctorId);
    if (!schedule) return [];
    const date = new Date(dateStr + 'T00:00:00');
    const day = date.getDay();
    const daySlot = schedule.slots.find((s) => s.day === day);
    if (!daySlot) return [];
    const slots = [];
    const [sh, sm] = daySlot.start.split(':').map(Number);
    const [eh, em] = daySlot.end.split(':').map(Number);
    const startMin = sh * 60 + sm, endMin = eh * 60 + em, duration = schedule.slotDuration || 30;
    const now = new Date();
    const isToday = dateStr === now.toISOString().slice(0, 10);
    const nowMin = now.getHours() * 60 + now.getMinutes();
    for (let t = startMin; t + duration <= endMin; t += duration) {
      if (isToday && t <= nowMin) continue;
      const h = Math.floor(t / 60), m = t % 60;
      slots.push({ time: `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`, label: formatTime(h, m) });
    }
    // Determine booked times. In Supabase mode, query the secure
    // public_appointment_slots view directly so anon (unauthenticated) patients
    // can check availability without needing SELECT access to the full
    // appointments table (RLS would return an empty set for them). In
    // localStorage mode, fall back to the in-memory bookings list.
    let bookedTimes = [];
    if (await useSupabase()) {
      const { data, error } = await _sb.from('public_appointment_slots')
        .select('time')
        .eq('doctor_id', doctorId)
        .eq('date', dateStr);
      if (error) throw error;
      bookedTimes = (data || []).map((s) => s.time);
    } else {
      bookedTimes = db.bookings
        .filter((b) => b.doctorId === doctorId && b.date === dateStr && b.status !== 'cancelled' && b.status !== 'no_show')
        .map((b) => b.time);
    }
    return slots.filter((s) => !bookedTimes.includes(s.time));
  }

  async function getAvailableDays(doctorId, daysAhead = 14) {
    const result = [];
    const today = new Date();
    for (let i = 0; i < daysAhead; i++) {
      const d = new Date(today); d.setDate(d.getDate() + i);
      const dateStr = d.toISOString().slice(0, 10);
      const slots = await getAvailableSlots(doctorId, dateStr);
      result.push({ date: dateStr, dayName: getDayName(d.getDay()), dayNumber: d.getDate(), monthName: getMonthName(d.getMonth()), slotsCount: slots.length, slots });
    }
    return result;
  }

  async function createBooking(data) {
    if (await useSupabase()) {
      const { data: apt, error } = await _sb.rpc('create_appointment', {
        p_doctor_id: data.doctorId,
        p_clinic_id: data.clinicId,
        p_patient_name: data.patientName,
        p_patient_phone: data.patientPhone,
        p_patient_age: data.patientAge || null,
        p_patient_notes: data.patientNotes || null,
        p_date: data.date,
        p_time: data.time,
        p_service: data.service,
        p_price: data.price,
        p_payment_method: data.paymentMethod || 'clinic',
      });
      if (error) throw error;
      invalidateCache();
      return mapBooking(apt);
    }
    const db = loadLocal();
    const booking = { id: 'b' + db.nextBookingId, ...data, status: 'confirmed', paymentMethod: data.paymentMethod || 'clinic', createdAt: new Date().toISOString() };
    db.nextBookingId++; db.bookings.push(booking);
    const doctor = db.doctors.find((d) => d.id === data.doctorId);
    const clinic = db.clinics.find((c) => c.id === data.clinicId);
    db.reminders.push({ id: 'rm' + db.nextReminderId, bookingId: booking.id, patientName: data.patientName, patientPhone: data.patientPhone, doctorName: doctor ? doctor.name : '', clinicName: clinic ? clinic.name : '', date: data.date, time: data.time, sent: false, createdAt: new Date().toISOString() });
    db.nextReminderId++; saveLocal(db);
    return booking;
  }

  async function updateBookingStatus(bookingId, status) {
    if (await useSupabase()) {
      const { data, error } = await _sb.rpc('update_appointment_status', {
        p_booking_id: bookingId,
        p_status: status,
      });
      if (error) throw error; invalidateCache(); return mapBooking(data);
    }
    const db = loadLocal();
    const b = db.bookings.find((x) => x.id === bookingId);
    if (b) { b.status = status; saveLocal(db); }
    return b;
  }

  async function getBookingsByClinic(clinicId) { return (await load()).bookings.filter((b) => b.clinicId === clinicId).sort((a, b) => (a.date + a.time > b.date + b.time ? 1 : -1)); }
  async function getBookingsByDoctor(doctorId) { return (await load()).bookings.filter((b) => b.doctorId === doctorId).sort((a, b) => (a.date + a.time > b.date + b.time ? 1 : -1)); }

  // ---- Patient: My Bookings ----
  async function getBookingsByPhone(phone, bookingId) {
    const cleanPhone = phone.replace(/[\s\-]/g, '');
    if (await useSupabase()) {
      if (!bookingId) throw new Error('رقم الحجز مطلوب');
      const { data, error } = await _sb.rpc('get_patient_booking', {
        p_booking_id: bookingId.replace(/^#/, ''),
        p_phone: cleanPhone,
      });
      if (error) throw error;
      return data ? [mapBooking(data)] : [];
    }
    const db = await load();
    return db.bookings
      .filter((b) => b.patientPhone === cleanPhone || b.patientPhone === phone)
      .sort((a, b) => (b.date + b.time > a.date + a.time ? 1 : -1));
  }

  async function cancelBooking(bookingId, phone) {
    if (await useSupabase()) {
      const { data, error } = await _sb.rpc('cancel_patient_booking', {
        p_booking_id: bookingId,
        p_phone: phone.replace(/[\s\-]/g, ''),
      });
      if (error) throw error;
      invalidateCache();
      return data;
    }
    const db = loadLocal();
    const b = db.bookings.find((x) => x.id === bookingId);
    if (b) { b.status = 'cancelled'; saveLocal(db); }
    return b;
  }

  async function addReview(data) {
    if (await useSupabase()) {
      const { data: review, error } = await _sb.rpc('create_verified_review', {
        p_booking_id: data.appointmentId,
        p_phone: data.patientPhone,
        p_rating: data.rating,
        p_comment: data.comment || '',
      });
      if (error) throw error;
      invalidateCache();
      return mapReview(review);
    }
    const db = loadLocal();
    const review = {
      id: 'r' + (db.reviews.length + 1),
      doctorId: data.doctorId,
      appointmentId: data.appointmentId || null,
      patientName: data.patientName,
      patientPhone: data.patientPhone,
      rating: data.rating,
      comment: data.comment || '',
      date: new Date().toISOString().slice(0, 10),
      verified: true,
    };
    db.reviews.push(review);
    // Update doctor's rating
    const doctor = db.doctors.find((d) => d.id === data.doctorId);
    if (doctor) {
      const docReviews = db.reviews.filter((r) => r.doctorId === data.doctorId);
      const sum = docReviews.reduce((s, r) => s + r.rating, 0);
      doctor.rating = Math.round((sum / docReviews.length) * 10) / 10;
      doctor.reviewsCount = docReviews.length;
    }
    saveLocal(db);
    return review;
  }

  async function hasReviewed(bookingId) {
    const db = await load();
    return db.reviews.some((r) => r.appointmentId === bookingId);
  }

  async function updateSchedule(doctorId, slots, slotDuration) {
    if (await useSupabase()) {
      const { error } = await _sb.rpc('replace_doctor_schedule', {
        p_doctor_id: doctorId,
        p_slots: slots,
        p_slot_duration: slotDuration,
      });
      if (error) throw error;
      invalidateCache(); return;
    }
    const db = loadLocal();
    let schedule = db.schedules.find((s) => s.doctorId === doctorId);
    if (schedule) { schedule.slots = slots; schedule.slotDuration = slotDuration; }
    else { db.schedules.push({ doctorId, slots, slotDuration }); }
    saveLocal(db);
  }

  // ---- Admin Operations with Activation Code ----
  async function approveClinic(clinicId) {
    if (await useSupabase()) {
      const { data, error } = await _sb.rpc('approve_clinic_registration', {
        p_clinic_id: clinicId,
      });
      if (error) throw error;
      invalidateCache();
      const clinic = mapClinic(data);
      clinic.activationCode = data.activation_code;
      return clinic;
    }
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let code = '';
    for (let i = 0; i < 6; i++) code += chars.charAt(Math.floor(Math.random() * chars.length));
    const db = loadLocal();
    const c = db.clinics.find((x) => x.id === clinicId);
    if (c) { c.status = 'approved'; c.activationCode = code; saveLocal(db); return c; }
    return null;
  }

  async function activateClinic(clinicName, activationCode, username, email, password) {
    if (await useSupabase()) {
      let authData = null;

      // A returning user may have confirmed the email after the first attempt.
      const signInResult = await _sb.auth.signInWithPassword({ email, password });
      if (!signInResult.error) authData = signInResult.data;

      if (!authData || !authData.session) {
        const signUpResult = await _sb.auth.signUp({ email, password });
        if (signUpResult.error && !/already|registered/i.test(signUpResult.error.message)) {
          throw new Error('فشل إنشاء الحساب: ' + signUpResult.error.message);
        }
        authData = signUpResult.data;
      }

      if (!authData || !authData.user || !authData.session) {
        throw new Error('أكد بريد الحساب ثم سجّل الدخول لإكمال تفعيل العيادة');
      }
      const { data: clinic, error: activationError } = await _sb.rpc('activate_clinic_account', {
        p_clinic_name: clinicName,
        p_activation_code: activationCode,
        p_username: username,
      });
      if (activationError) throw new Error('فشل التفعيل: ' + activationError.message);
      invalidateCache();
      return { success: true, clinic: mapClinic(clinic) };
    }
    const db = loadLocal();
    const clinic = db.clinics.find((c) => c.activationCode === activationCode && c.status === 'approved');
    if (!clinic) throw new Error('رمز التفعيل غير صحيح أو العيادة غير موافق عليها');
    if (clinic.name !== clinicName) throw new Error('اسم العيادة لا يطابق السجل');
    if (db.clinicUsers.find((u) => u.username === username)) throw new Error('اسم المستخدم محجوز، اختر اسماً آخر');
    db.clinicUsers.push({ id: 'cu' + (db.clinicUsers.length + 1), clinicId: clinic.id, username, password, name: clinic.name + ' - مدير' });
    clinic.activationCode = null;
    saveLocal(db);
    return { success: true, clinic };
  }

  async function rejectClinic(clinicId) {
    if (await useSupabase()) {
      const { data, error } = await _sb.rpc('reject_clinic_registration', {
        p_clinic_id: clinicId,
      });
      if (error) throw error; invalidateCache(); return mapClinic(data);
    }
    const db = loadLocal();
    const c = db.clinics.find((x) => x.id === clinicId);
    if (c) { c.status = 'rejected'; saveLocal(db); }
    return c;
  }

  async function addClinic(data) {
    if (await useSupabase()) {
      const { data: clinic, error } = await _sb.rpc('register_clinic', {
        p_name: data.name,
        p_city_id: data.cityId,
        p_area: data.area,
        p_address: data.address,
        p_phone: data.phone,
        p_lat: data.lat || 0,
        p_lng: data.lng || 0,
      });
      if (error) throw error; invalidateCache(); return mapClinic(clinic);
    }
    const db = loadLocal();
    const clinic = { id: 'cl' + (db.clinics.length + 1), ...data, status: 'pending', createdAt: new Date().toISOString() };
    db.clinics.push(clinic); saveLocal(db); return clinic;
  }

  async function addDoctor(data) {
    if (await useSupabase()) {
      const { data: doctor, error } = await _sb.rpc('create_doctor', {
        p_name: data.name,
        p_name_en: data.nameEn || '',
        p_specialty_id: data.specialtyId,
        p_clinic_id: data.clinicId,
        p_photo: data.photo || '',
        p_bio: data.bio || '',
        p_qualifications: data.qualifications || '',
        p_experience_years: data.experienceYears || 0,
        p_price: data.price,
        p_gender: data.gender || 'male',
        p_languages: data.languages || ['العربية'],
        p_services: data.services || ['clinic'],
      });
      if (error) throw error; invalidateCache(); return mapDoctor(doctor);
    }
    const db = loadLocal();
    const doctor = { id: 'd' + (db.doctors.length + 1), ...data, rating: 0, reviewsCount: 0, verified: false, featured: false };
    db.doctors.push(doctor); saveLocal(db); return doctor;
  }

  async function deleteDoctor(doctorId) {
    if (await useSupabase()) {
      const { error } = await _sb.rpc('delete_or_deactivate_doctor', {
        p_doctor_id: doctorId,
      });
      if (error) throw error; invalidateCache(); return true;
    }
    const db = loadLocal();
    db.doctors = db.doctors.filter((d) => d.id !== doctorId);
    db.schedules = db.schedules.filter((s) => s.doctorId !== doctorId);
    db.reviews = db.reviews.filter((r) => r.doctorId !== doctorId);
    saveLocal(db); return true;
  }

  async function updateDoctor(doctorId, updates) {
    if (await useSupabase()) {
      const { data, error } = await _sb.rpc('update_doctor', {
        p_doctor_id: doctorId,
        p_updates: updates,
      });
      if (error) throw error; invalidateCache(); return mapDoctor(data);
    }
    const db = loadLocal();
    const d = db.doctors.find((x) => x.id === doctorId);
    if (d) { Object.assign(d, updates); saveLocal(db); }
    return d;
  }

  async function clinicLogin(username, password) {
    if (await useSupabase()) {
      const email = username.includes('@') ? username : `${username}@sahatna.app`;
      const { data: authData, error: authError } = await _sb.auth.signInWithPassword({ email, password });
      if (authError || !authData.user) {
        if (authError) console.error('Login error:', authError);
        return null;
      }
      const { data: clinicUser, error: clinicUserError } = await _sb.from('clinic_users').select('*').eq('user_id', authData.user.id).single();
      if (!clinicUser) {
        if (clinicUserError) console.error('clinic_users lookup error:', clinicUserError);
        await _sb.auth.signOut();
        return null;
      }
      const { data: clinic, error: clinicError } = await _sb.from('clinics').select('*').eq('id', clinicUser.clinic_id).single();
      if (!clinic && clinicError) console.error('clinic lookup error:', clinicError);
      invalidateCache();
      return { user: { id: clinicUser.id, clinicId: clinicUser.clinic_id, userId: clinicUser.user_id, username: clinicUser.username, name: clinicUser.name }, clinic: clinic ? mapClinic(clinic) : null };
    }
    const db = loadLocal();
    const user = db.clinicUsers.find((u) => u.username === username && u.password === password);
    if (user) { const clinic = db.clinics.find((c) => c.id === user.clinicId); return { user, clinic }; }
    return null;
  }

  async function adminLogin(username, password) {
    if (await useSupabase()) {
      const email = username.includes('@') ? username : `${username}@sahatna.app`;
      const { data: authData, error: authError } = await _sb.auth.signInWithPassword({ email, password });
      if (authError || !authData.user) {
        if (authError) console.error('Login error:', authError);
        return null;
      }
      const { data: adminUser, error: adminUserError } = await _sb.from('admin_users').select('*').eq('user_id', authData.user.id).single();
      if (!adminUser) {
        if (adminUserError) console.error('admin_users lookup error:', adminUserError);
        await _sb.auth.signOut();
        return null;
      }
      invalidateCache();
      return { id: adminUser.id, userId: adminUser.user_id, username: adminUser.username, name: adminUser.name };
    }
    const db = loadLocal();
    return db.adminUsers.find((u) => u.username === username && u.password === password) || null;
  }

  async function getCurrentClinicSession() {
    if (!(await useSupabase())) return null;
    const { data: authData, error: authError } = await _sb.auth.getUser();
    if (authError || !authData.user) return null;
    const { data: clinicUser, error: clinicUserError } = await _sb
      .from('clinic_users').select('*').eq('user_id', authData.user.id).maybeSingle();
    if (clinicUserError || !clinicUser) return null;
    const { data: clinic, error: clinicError } = await _sb
      .from('clinics').select('*').eq('id', clinicUser.clinic_id).maybeSingle();
    if (clinicError || !clinic) return null;
    return {
      user: {
        id: clinicUser.id,
        clinicId: clinicUser.clinic_id,
        userId: clinicUser.user_id,
        username: clinicUser.username,
        name: clinicUser.name,
      },
      clinic: mapClinic(clinic),
    };
  }

  async function getCurrentAdmin() {
    if (!(await useSupabase())) return null;
    const { data: authData, error: authError } = await _sb.auth.getUser();
    if (authError || !authData.user) return null;
    const { data: adminUser, error } = await _sb
      .from('admin_users').select('*').eq('user_id', authData.user.id).maybeSingle();
    if (error || !adminUser) return null;
    return {
      id: adminUser.id,
      userId: adminUser.user_id,
      username: adminUser.username,
      name: adminUser.name,
    };
  }

  async function signOut() {
    if (await useSupabase()) await _sb.auth.signOut();
    invalidateCache();
  }

  async function getPendingReminders() { return (await load()).reminders.filter((r) => !r.sent); }

  async function markReminderSent(reminderId) {
    if (await useSupabase()) {
      const { data, error } = await _sb.rpc('mark_reminder_sent', {
        p_reminder_id: reminderId,
      });
      if (error) throw error; invalidateCache(); return mapReminder(data);
    }
    const db = loadLocal();
    const r = db.reminders.find((x) => x.id === reminderId);
    if (r) { r.sent = true; r.sentAt = new Date().toISOString(); saveLocal(db); }
    return r;
  }

  async function getStats() {
    const db = await load();
    const totalRevenue = db.bookings.filter((b) => b.status === 'completed').reduce((sum, b) => sum + (b.price || 0), 0);
    return {
      totalDoctors: db.doctors.length, totalClinics: db.clinics.length,
      approvedClinics: db.clinics.filter((c) => c.status === 'approved').length,
      pendingClinics: db.clinics.filter((c) => c.status === 'pending').length,
      totalBookings: db.bookings.length,
      confirmedBookings: db.bookings.filter((b) => b.status === 'confirmed').length,
      completedBookings: db.bookings.filter((b) => b.status === 'completed').length,
      cancelledBookings: db.bookings.filter((b) => b.status === 'cancelled').length,
      totalRevenue, totalPatients: new Set(db.bookings.map((b) => b.patientPhone)).size,
    };
  }

  async function reset() { if (await useSupabase()) { invalidateCache(); return; } return resetLocal(); }

  return {
    escapeHTML, safeImageURL,
    isSupabaseEnabled: isSupabaseConfigured,
    load, reset, getSpecialty, getCity, getClinic, getDoctor, getSchedule,
    getAvailableSlots, getAvailableDays, formatTime, getDayName, getMonthName,
    createBooking, updateBookingStatus, getBookingsByClinic, getBookingsByDoctor,
    updateSchedule, approveClinic, rejectClinic, activateClinic, addClinic,
    addDoctor, deleteDoctor, updateDoctor, clinicLogin, adminLogin, signOut,
    getCurrentClinicSession, getCurrentAdmin,
    getPendingReminders, markReminderSent, getStats,
    getBookingsByPhone, cancelBooking, addReview, hasReviewed,
  };
})();
