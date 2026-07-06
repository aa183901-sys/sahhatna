/**
 * صحتنا - Sahatna Data Layer
 * Mock database using localStorage with seed data for the Iraqi market.
 * All prices in Iraqi Dinar (IQD), cities/specialties localized for Iraq.
 */

const SahatnaDB = (function () {
  const STORAGE_KEY = 'sahatna_db_v1';

  // ---- Seed Data ----------------------------------------------------------
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
      { id: 'c1', name: 'بغداد' },
      { id: 'c2', name: 'البصرة' },
      { id: 'c3', name: 'الموصل' },
      { id: 'c4', name: 'أربيل' },
      { id: 'c5', name: 'النجف' },
      { id: 'c6', name: 'كربلاء' },
      { id: 'c7', name: 'كركوك' },
      { id: 'c8', name: 'السليمانية' },
      { id: 'c9', name: 'الديوانية' },
      { id: 'c10', name: 'العمارة' },
      { id: 'c11', name: 'الناصرية' },
      { id: 'c12', name: 'الحلة' },
    ],
    clinics: [
      {
        id: 'cl1',
        name: 'مركز الشفاء الطبي',
        cityId: 'c1',
        area: 'الكرادة',
        address: 'شارع الكرادة داخل، قرب مجمع الكرادة',
        phone: '07701234567',
        lat: 33.3152,
        lng: 44.4360,
        status: 'approved',
        createdAt: '2025-01-15T08:00:00Z',
      },
      {
        id: 'cl2',
        name: 'عيادة النور للتخصصات',
        cityId: 'c1',
        area: 'المنصور',
        address: 'شارع الأميرات، المنصور',
        phone: '07801234567',
        lat: 33.3230,
        lng: 44.3850,
        status: 'approved',
        createdAt: '2025-02-01T08:00:00Z',
      },
      {
        id: 'cl3',
        name: 'مستشفى الحياة الخاص',
        cityId: 'c2',
        area: 'العشار',
        address: 'شارع الكورنيش، العشار',
        phone: '07901234567',
        lat: 30.5085,
        lng: 47.7804,
        status: 'approved',
        createdAt: '2025-02-10T08:00:00Z',
      },
      {
        id: 'cl4',
        name: 'مركز الرافدين الطبي',
        cityId: 'c5',
        area: 'المركز',
        address: 'شارع الكوفة، النجف',
        phone: '07712345678',
        lat: 32.0000,
        lng: 44.3333,
        status: 'pending',
        createdAt: '2025-07-01T08:00:00Z',
      },
    ],
    doctors: [
      {
        id: 'd1',
        name: 'د. أحمد الكاظمي',
        nameEn: 'Dr. Ahmed Al-Kadhimi',
        specialtyId: 'sp2',
        clinicId: 'cl1',
        photo: 'https://ui-avatars.com/api/?name=Ahmed+K&background=0d9488&color=fff&size=200',
        bio: 'استشاري باطنية مع خبرة 15 سنة في تشخيص وعلاج الأمراض المزمنة مثل السكري وضغط الدم.',
        qualifications: 'بورد عراقي في الباطنية - جامعة بغداد',
        experienceYears: 15,
        price: 30000,
        gender: 'male',
        languages: ['العربية', 'English'],
        rating: 4.8,
        reviewsCount: 124,
        services: ['clinic', 'video'],
        verified: true,
        featured: true,
      },
      {
        id: 'd2',
        name: 'د. سارة العبيدي',
        nameEn: 'Dr. Sara Al-Obaidi',
        specialtyId: 'sp4',
        clinicId: 'cl1',
        photo: 'https://ui-avatars.com/api/?name=Sara+O&background=db2777&color=fff&size=200',
        bio: 'أخصائية نسائية وتوليد، متخصصة في متابعة الحمل والعناية بصحة المرأة.',
        qualifications: 'بورد عراقي في النسائية - جامعة بغداد',
        experienceYears: 10,
        price: 35000,
        gender: 'female',
        languages: ['العربية'],
        rating: 4.9,
        reviewsCount: 89,
        services: ['clinic', 'video', 'home'],
        verified: true,
        featured: true,
      },
      {
        id: 'd3',
        name: 'د. محمد الجبوري',
        nameEn: 'Dr. Mohammed Al-Jubouri',
        specialtyId: 'sp3',
        clinicId: 'cl2',
        photo: 'https://ui-avatars.com/api/?name=Mohammed+J&background=2563eb&color=fff&size=200',
        bio: 'طبيب أطفال متخصص في رعاية حديثي الولادة والأمراض المعدية لدى الأطفال.',
        qualifications: 'بورد عراقي في الأطفال - جامعة الموصل',
        experienceYears: 12,
        price: 25000,
        gender: 'male',
        languages: ['العربية', 'English', 'كوردی'],
        rating: 4.7,
        reviewsCount: 156,
        services: ['clinic', 'video'],
        verified: true,
        featured: false,
      },
      {
        id: 'd4',
        name: 'د. زينب الحسني',
        nameEn: 'Dr. Zainab Al-Hasnawi',
        specialtyId: 'sp5',
        clinicId: 'cl2',
        photo: 'https://ui-avatars.com/api/?name=Zainab+H&background=7c3aed&color=fff&size=200',
        bio: 'أخصائية جلدية، علاج حب الشباب، التصبغات، وإجراءات التجميل غير الجراحي.',
        qualifications: 'بورد عراقي في الجلدية - جامعة البصرة',
        experienceYears: 8,
        price: 40000,
        gender: 'female',
        languages: ['العربية'],
        rating: 4.6,
        reviewsCount: 67,
        services: ['clinic'],
        verified: true,
        featured: false,
      },
      {
        id: 'd5',
        name: 'د. عمر التميمي',
        nameEn: 'Dr. Omar Al-Tamimi',
        specialtyId: 'sp6',
        clinicId: 'cl3',
        photo: 'https://ui-avatars.com/api/?name=Omar+T&background=0891b2&color=fff&size=200',
        bio: 'طبيب أسنان تقويم وزراعة، خبرة في علاج التشوهات وتركيب الأسنان.',
        qualifications: 'ماجستير في تقويم الأسنان - جامعة بغداد',
        experienceYears: 14,
        price: 20000,
        gender: 'male',
        languages: ['العربية', 'English'],
        rating: 4.5,
        reviewsCount: 203,
        services: ['clinic'],
        verified: true,
        featured: true,
      },
      {
        id: 'd6',
        name: 'د. نور الساعدي',
        nameEn: 'Dr. Noor Al-Saadi',
        specialtyId: 'sp1',
        clinicId: 'cl3',
        photo: 'https://ui-avatars.com/api/?name=Noor+S&background=059669&color=fff&size=200',
        bio: 'طبيبة طب أسرة، متابعة الأمراض المزمنة والوقائية لكل أفراد العائلة.',
        qualifications: 'بورد عراقي في طب الأسرة',
        experienceYears: 7,
        price: 20000,
        gender: 'female',
        languages: ['العربية', 'English'],
        rating: 4.9,
        reviewsCount: 45,
        services: ['clinic', 'video', 'home'],
        verified: true,
        featured: false,
      },
    ],
    // Schedule: each doctor has weekly slots. 0=Sunday ... 6=Saturday
    schedules: [
      {
        doctorId: 'd1',
        slots: [
          { day: 0, start: '17:00', end: '21:00' },
          { day: 1, start: '17:00', end: '21:00' },
          { day: 2, start: '17:00', end: '21:00' },
          { day: 3, start: '17:00', end: '21:00' },
          { day: 5, start: '10:00', end: '14:00' },
        ],
        slotDuration: 30, // minutes
      },
      {
        doctorId: 'd2',
        slots: [
          { day: 0, start: '16:00', end: '20:00' },
          { day: 2, start: '16:00', end: '20:00' },
          { day: 4, start: '16:00', end: '20:00' },
          { day: 6, start: '11:00', end: '15:00' },
        ],
        slotDuration: 30,
      },
      {
        doctorId: 'd3',
        slots: [
          { day: 1, start: '10:00', end: '14:00' },
          { day: 3, start: '10:00', end: '14:00' },
          { day: 5, start: '10:00', end: '14:00' },
          { day: 6, start: '10:00', end: '14:00' },
        ],
        slotDuration: 20,
      },
      {
        doctorId: 'd4',
        slots: [
          { day: 0, start: '11:00', end: '15:00' },
          { day: 2, start: '11:00', end: '15:00' },
          { day: 4, start: '11:00', end: '15:00' },
        ],
        slotDuration: 30,
      },
      {
        doctorId: 'd5',
        slots: [
          { day: 1, start: '09:00', end: '13:00' },
          { day: 2, start: '09:00', end: '13:00' },
          { day: 3, start: '09:00', end: '13:00' },
          { day: 4, start: '09:00', end: '13:00' },
          { day: 5, start: '09:00', end: '13:00' },
        ],
        slotDuration: 30,
      },
      {
        doctorId: 'd6',
        slots: [
          { day: 0, start: '12:00', end: '16:00' },
          { day: 1, start: '12:00', end: '16:00' },
          { day: 2, start: '12:00', end: '16:00' },
          { day: 3, start: '12:00', end: '16:00' },
          { day: 4, start: '12:00', end: '16:00' },
        ],
        slotDuration: 20,
      },
    ],
    reviews: [
      { id: 'r1', doctorId: 'd1', patientName: 'علي حسين', rating: 5, comment: 'طبيب محترم وخبير، شخّص حالتي بدقة.', date: '2025-06-20', verified: true },
      { id: 'r2', doctorId: 'd1', patientName: 'فاطمة عبد الله', rating: 4, comment: 'استشارة جيدة لكن الانتظار كان طويل شوية.', date: '2025-06-18', verified: true },
      { id: 'r3', doctorId: 'd2', patientName: 'مريم أحمد', rating: 5, comment: 'د. سارة رائعة، متابعة الحمل معها مريحة جداً.', date: '2025-06-22', verified: true },
      { id: 'r4', doctorId: 'd3', patientName: 'كريم سعد', rating: 5, comment: 'تعامله مع الأطفال ممتاز، ابني ما خاف من الطبيب.', date: '2025-06-19', verified: true },
      { id: 'r5', doctorId: 'd5', patientName: 'حسن كاظم', rating: 4, comment: 'علاج الأسنان كان جيد والأسعار معقولة.', date: '2025-06-15', verified: true },
    ],
    bookings: [],
    // Clinic login: phone = password (demo). In production this would be hashed.
    clinicUsers: [
      { id: 'cu1', clinicId: 'cl1', username: 'cl1', password: '1234', name: 'مدير مركز الشفاء' },
      { id: 'cu2', clinicId: 'cl2', username: 'cl2', password: '1234', name: 'مدير عيادة النور' },
      { id: 'cu3', clinicId: 'cl3', username: 'cl3', password: '1234', name: 'مدير مستشفى الحياة' },
    ],
    adminUsers: [
      { username: 'admin', password: 'admin123', name: 'مدير صحتنا' },
    ],
    reminders: [],
    nextBookingId: 1,
    nextReminderId: 1,
  };

  // ---- Persistence -------------------------------------------------------
  function load() {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      save(seed);
      return JSON.parse(JSON.stringify(seed));
    }
    try {
      return JSON.parse(raw);
    } catch (e) {
      console.error('DB parse error, reseeding', e);
      save(seed);
      return JSON.parse(JSON.stringify(seed));
    }
  }

  function save(db) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(db));
  }

  function reset() {
    localStorage.removeItem(STORAGE_KEY);
    return load();
  }

  // ---- Helpers -----------------------------------------------------------
  function getSpecialty(id) {
    return load().specialties.find((s) => s.id === id);
  }
  function getCity(id) {
    return load().cities.find((c) => c.id === id);
  }
  function getClinic(id) {
    return load().clinics.find((c) => c.id === id);
  }
  function getDoctor(id) {
    return load().doctors.find((d) => d.id === id);
  }
  function getSchedule(doctorId) {
    return load().schedules.find((s) => s.doctorId === doctorId);
  }

  // Generate available time slots for a given date (YYYY-MM-DD)
  function getAvailableSlots(doctorId, dateStr) {
    const schedule = getSchedule(doctorId);
    if (!schedule) return [];
    const date = new Date(dateStr + 'T00:00:00');
    const day = date.getDay(); // 0=Sunday
    const daySlot = schedule.slots.find((s) => s.day === day);
    if (!daySlot) return [];

    const slots = [];
    const [sh, sm] = daySlot.start.split(':').map(Number);
    const [eh, em] = daySlot.end.split(':').map(Number);
    const startMin = sh * 60 + sm;
    const endMin = eh * 60 + em;
    const duration = schedule.slotDuration || 30;

    // Don't show past slots if the date is today
    const now = new Date();
    const isToday = dateStr === now.toISOString().slice(0, 10);
    const nowMin = now.getHours() * 60 + now.getMinutes();

    for (let t = startMin; t + duration <= endMin; t += duration) {
      if (isToday && t <= nowMin) continue;
      const h = Math.floor(t / 60);
      const m = t % 60;
      slots.push({
        time: `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`,
        label: formatTime(h, m),
      });
    }

    // Filter out already-booked slots
    const db = load();
    const booked = db.bookings.filter(
      (b) => b.doctorId === doctorId && b.date === dateStr && b.status !== 'cancelled'
    );
    const bookedTimes = booked.map((b) => b.time);
    return slots.filter((s) => !bookedTimes.includes(s.time));
  }

  function formatTime(h, m) {
    const period = h >= 12 ? 'م' : 'ص';
    let h12 = h % 12;
    if (h12 === 0) h12 = 12;
    return `${h12}:${String(m).padStart(2, '0')} ${period}`;
  }

  // Get next 14 days with available slots for a doctor
  function getAvailableDays(doctorId, daysAhead = 14) {
    const result = [];
    const today = new Date();
    for (let i = 0; i < daysAhead; i++) {
      const d = new Date(today);
      d.setDate(d.getDate() + i);
      const dateStr = d.toISOString().slice(0, 10);
      const slots = getAvailableSlots(doctorId, dateStr);
      result.push({
        date: dateStr,
        dayName: getDayName(d.getDay()),
        dayNumber: d.getDate(),
        monthName: getMonthName(d.getMonth()),
        slotsCount: slots.length,
        slots: slots,
      });
    }
    return result;
  }

  function getDayName(day) {
    const names = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    return names[day];
  }

  function getMonthName(month) {
    const names = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    return names[month];
  }

  // ---- Booking operations ------------------------------------------------
  function createBooking(data) {
    const db = load();
    const booking = {
      id: 'b' + db.nextBookingId,
      ...data,
      status: 'confirmed', // instant confirmation
      paymentMethod: data.paymentMethod || 'clinic',
      createdAt: new Date().toISOString(),
    };
    db.nextBookingId++;
    db.bookings.push(booking);

    // Create a reminder
    const reminder = {
      id: 'rm' + db.nextReminderId,
      bookingId: booking.id,
      patientName: data.patientName,
      patientPhone: data.patientPhone,
      doctorName: getDoctor(data.doctorId).name,
      clinicName: getClinic(getDoctor(data.doctorId).clinicId).name,
      date: data.date,
      time: data.time,
      sent: false,
      createdAt: new Date().toISOString(),
    };
    db.nextReminderId++;
    db.reminders.push(reminder);

    save(db);
    return booking;
  }

  function updateBookingStatus(bookingId, status) {
    const db = load();
    const b = db.bookings.find((x) => x.id === bookingId);
    if (b) {
      b.status = status;
      save(db);
    }
    return b;
  }

  function getBookingsByClinic(clinicId) {
    const db = load();
    const doctorIds = db.doctors.filter((d) => d.clinicId === clinicId).map((d) => d.id);
    return db.bookings
      .filter((b) => doctorIds.includes(b.doctorId))
      .sort((a, b) => (a.date + a.time > b.date + b.time ? 1 : -1));
  }

  function getBookingsByDoctor(doctorId) {
    return load()
      .bookings.filter((b) => b.doctorId === doctorId)
      .sort((a, b) => (a.date + a.time > b.date + b.time ? 1 : -1));
  }

  // ---- Clinic schedule management ----------------------------------------
  function updateSchedule(doctorId, slots, slotDuration) {
    const db = load();
    let schedule = db.schedules.find((s) => s.doctorId === doctorId);
    if (schedule) {
      schedule.slots = slots;
      schedule.slotDuration = slotDuration;
    } else {
      db.schedules.push({ doctorId, slots, slotDuration });
    }
    save(db);
  }

  // ---- Admin operations --------------------------------------------------
  function approveClinic(clinicId) {
    const db = load();
    const c = db.clinics.find((x) => x.id === clinicId);
    if (c) {
      c.status = 'approved';
      save(db);
    }
    return c;
  }

  function rejectClinic(clinicId) {
    const db = load();
    const c = db.clinics.find((x) => x.id === clinicId);
    if (c) {
      c.status = 'rejected';
      save(db);
    }
    return c;
  }

  function addClinic(data) {
    const db = load();
    const clinic = {
      id: 'cl' + (db.clinics.length + 1),
      ...data,
      status: 'pending',
      createdAt: new Date().toISOString(),
    };
    db.clinics.push(clinic);
    save(db);
    return clinic;
  }

  function addDoctor(data) {
    const db = load();
    const doctor = {
      id: 'd' + (db.doctors.length + 1),
      ...data,
      rating: 0,
      reviewsCount: 0,
      verified: false,
      featured: false,
    };
    db.doctors.push(doctor);
    save(db);
    return doctor;
  }

  // ---- Auth --------------------------------------------------------------
  function clinicLogin(username, password) {
    const db = load();
    const user = db.clinicUsers.find(
      (u) => u.username === username && u.password === password
    );
    if (user) {
      const clinic = getClinic(user.clinicId);
      return { user, clinic };
    }
    return null;
  }

  function adminLogin(username, password) {
    const db = load();
    return db.adminUsers.find(
      (u) => u.username === username && u.password === password
    ) || null;
  }

  // ---- Reminders ---------------------------------------------------------
  function getPendingReminders() {
    return load().reminders.filter((r) => !r.sent);
  }

  function markReminderSent(reminderId) {
    const db = load();
    const r = db.reminders.find((x) => x.id === reminderId);
    if (r) {
      r.sent = true;
      r.sentAt = new Date().toISOString();
      save(db);
    }
    return r;
  }

  // ---- Stats -------------------------------------------------------------
  function getStats() {
    const db = load();
    const totalRevenue = db.bookings
      .filter((b) => b.status === 'completed')
      .reduce((sum, b) => sum + (b.price || 0), 0);
    return {
      totalDoctors: db.doctors.length,
      totalClinics: db.clinics.length,
      approvedClinics: db.clinics.filter((c) => c.status === 'approved').length,
      pendingClinics: db.clinics.filter((c) => c.status === 'pending').length,
      totalBookings: db.bookings.length,
      confirmedBookings: db.bookings.filter((b) => b.status === 'confirmed').length,
      completedBookings: db.bookings.filter((b) => b.status === 'completed').length,
      cancelledBookings: db.bookings.filter((b) => b.status === 'cancelled').length,
      totalRevenue,
      totalPatients: new Set(db.bookings.map((b) => b.patientPhone)).size,
    };
  }

  // ---- Public API --------------------------------------------------------
  return {
    load,
    save,
    reset,
    getSpecialty,
    getCity,
    getClinic,
    getDoctor,
    getSchedule,
    getAvailableSlots,
    getAvailableDays,
    formatTime,
    getDayName,
    getMonthName,
    createBooking,
    updateBookingStatus,
    getBookingsByClinic,
    getBookingsByDoctor,
    updateSchedule,
    approveClinic,
    rejectClinic,
    addClinic,
    addDoctor,
    clinicLogin,
    adminLogin,
    getPendingReminders,
    markReminderSent,
    getStats,
  };
})();