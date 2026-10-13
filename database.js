// ================================================================
//  RabtaChat Pro — Complete Database (localStorage)
//  File  : database.js
//  Forms : Login (3-step) | Signup (4-step) | Forgot Password | Newsletter
//  Tables: users | sessions | otps | password_resets | contacts
//          messages | newsletter | activity_log
// ================================================================

'use strict';

/* ---------------------------------------------------------------
   CORE DATABASE ENGINE
--------------------------------------------------------------- */
const DB = {

  _read(table) {
    try { return JSON.parse(localStorage.getItem('rabta_' + table)) || []; }
    catch { return []; }
  },

  _write(table, data) {
    localStorage.setItem('rabta_' + table, JSON.stringify(data));
  },

  _id(prefix) {
    return prefix + '_' + Date.now() + '_' + Math.random().toString(36).slice(2,6);
  },

  _now() { return new Date().toISOString(); },

  reset() {
    ['users','sessions','otps','password_resets','contacts',
     'messages','newsletter','activity'].forEach(t =>
      localStorage.removeItem('rabta_' + t)
    );
    console.log('RabtaDB: All tables cleared.');
  },

  inspect() {
    console.group('RabtaChat Pro — Database');
    console.log('%cUSERS','color:#6366f1;font-weight:bold');       console.table(DB.users.getAll());
    console.log('%cSESSIONS','color:#10b981;font-weight:bold');    console.table(DB.sessions.getAll());
    console.log('%cOTPs','color:#f59e0b;font-weight:bold');        console.table(DB.otps.getAll());
    console.log('%cPASSWORD RESETS','color:#ef4444;font-weight:bold'); console.table(DB.passwordResets.getAll());
    console.log('%cCONTACTS','color:#06b6d4;font-weight:bold');    console.table(DB.contacts.getAll());
    console.log('%cNEWSLETTER','color:#ec4899;font-weight:bold');  console.table(DB.newsletter.getAll());
    console.log('%cACTIVITY','color:#8b5cf6;font-weight:bold');    console.table(DB.activity.getAll());
    console.groupEnd();
  },

  /* ============================================================
     TABLE 1 — USERS
     From: Login form | Signup form
  ============================================================ */
  users: {
    getAll() { return DB._read('users'); },

    create(data) {
      const users = this.getAll();
      const user = {
        id:          DB._id('usr'),
        name:        data.name       || '',
        email:       data.email      || '',
        username:    data.username   || '',
        password:    data.password   || '',
        phone:       data.phone      || '',
        avatar:      data.name ? data.name.charAt(0).toUpperCase() : 'U',
        role:        'user',
        isVerified:  data.isVerified || false,
        isActive:    true,
        createdAt:   DB._now(),
        updatedAt:   DB._now(),
        lastLoginAt: null,
        preferences: { theme:'dark', language:'English', notifications:true },
      };
      users.push(user);
      DB._write('users', users);
      DB.activity.log('SIGNUP', 'New user: @' + user.username);
      return user;
    },

    findById(id)       { return this.getAll().find(u => u.id === id)                     || null; },
    findByEmail(em)    { return this.getAll().find(u => u.email    === em.toLowerCase()) || null; },
    findByUsername(un) { return this.getAll().find(u => u.username === un.toLowerCase()) || null; },

    emailExists(em)    { return !!this.findByEmail(em); },
    usernameExists(un) { return !!this.findByUsername(un); },

    update(id, fields) {
      const users = this.getAll();
      const i = users.findIndex(u => u.id === id);
      if (i === -1) return null;
      users[i] = { ...users[i], ...fields, updatedAt: DB._now() };
      DB._write('users', users);
      return users[i];
    },

    verify(email) {
      const u = this.findByEmail(email);
      return u ? this.update(u.id, { isVerified:true }) : false;
    },

    safe(user) {
      if (!user) return null;
      const { password, ...safe } = user;
      return safe;
    },
  },

  /* ============================================================
     TABLE 2 — SESSIONS
     From: Login complete | Signup complete
  ============================================================ */
  sessions: {
    getAll() { return DB._read('sessions'); },

    create(user) {
      const sessions = this.getAll();
      const session = {
        id:        DB._id('sess'),
        userId:    user.id,
        name:      user.name,
        username:  user.username,
        email:     user.email,
        role:      user.role,
        loginAt:   DB._now(),
        expiresAt: new Date(Date.now() + 30*24*60*60*1000).toISOString(),
        device:    navigator.userAgent.substring(0,100),
        isActive:  true,
      };
      sessions.push(session);
      DB._write('sessions', sessions);
      localStorage.setItem('rabta_current_session', JSON.stringify(session));
      DB.users.update(user.id, { lastLoginAt: DB._now() });
      DB.activity.log('LOGIN', '@' + user.username + ' logged in');
      return session;
    },

    getCurrent() {
      try { return JSON.parse(localStorage.getItem('rabta_current_session')); }
      catch { return null; }
    },

    isValid() {
      const s = this.getCurrent();
      return s && new Date() < new Date(s.expiresAt);
    },

    destroy() {
      const s = this.getCurrent();
      if (s) {
        const sessions = this.getAll();
        const i = sessions.findIndex(x => x.id === s.id);
        if (i !== -1) { sessions[i].isActive = false; sessions[i].logoutAt = DB._now(); }
        DB._write('sessions', sessions);
        DB.activity.log('LOGOUT', '@' + s.username + ' logged out');
      }
      localStorage.removeItem('rabta_current_session');
    },

    getByUser(userId) { return this.getAll().filter(s => s.userId === userId); },
  },

  /* ============================================================
     TABLE 3 — OTPs
     From: Signup Step 1
  ============================================================ */
  otps: {
    EXPIRY_MS: 10 * 60 * 1000,
    getAll()  { return DB._read('otps'); },

    generate(email) {
      const otps = this.getAll();
      const code = String(Math.floor(100000 + Math.random() * 900000));
      otps.push({
        id:        DB._id('otp'),
        email:     email.toLowerCase(),
        code:      code,
        purpose:   'email_verification',
        createdAt: DB._now(),
        expiresAt: new Date(Date.now() + this.EXPIRY_MS).toISOString(),
        used:      false,
        attempts:  0,
      });
      DB._write('otps', otps);
      console.log('OTP for ' + email + ': ' + code + ' (10 min)');
      return code;
    },

    verify(email, code) {
      const otps = DB._read('otps');
      let foundIdx = -1;
      for (let i = otps.length - 1; i >= 0; i--) {
        if (otps[i].email === email.toLowerCase() &&
            otps[i].code  === String(code) &&
            !otps[i].used) {
          foundIdx = i; break;
        }
      }
      if (foundIdx === -1) return { ok:false, reason:'OTP not found or already used' };
      if (new Date() > new Date(otps[foundIdx].expiresAt)) {
        otps[foundIdx].attempts++;
        DB._write('otps', otps);
        return { ok:false, reason:'OTP expired' };
      }
      otps[foundIdx].used   = true;
      otps[foundIdx].usedAt = DB._now();
      DB._write('otps', otps);
      DB.activity.log('OTP_VERIFIED', 'Email ' + email + ' verified');
      return { ok:true };
    },
  },

  /* ============================================================
     TABLE 4 — PASSWORD RESETS
     From: Forgot Password form
  ============================================================ */
  passwordResets: {
    EXPIRY_MS: 60 * 60 * 1000,
    getAll()  { return DB._read('password_resets'); },

    create(email) {
      const resets = this.getAll();
      const token  = Math.random().toString(36).slice(2,12).toUpperCase() +
                     Math.random().toString(36).slice(2,12).toUpperCase();
      const entry = {
        id:          DB._id('rst'),
        email:       email.toLowerCase(),
        token:       token,
        requestedAt: DB._now(),
        expiresAt:   new Date(Date.now() + this.EXPIRY_MS).toISOString(),
        used:        false,
        usedAt:      null,
      };
      resets.push(entry);
      DB._write('password_resets', resets);
      console.log('Reset token for ' + email + ': ' + token);
      DB.activity.log('PWD_RESET_REQ', 'Reset for ' + email);
      return entry;
    },

    validate(email, token) {
      const resets = this.getAll();
      for (let i = resets.length - 1; i >= 0; i--) {
        if (resets[i].email === email.toLowerCase() &&
            resets[i].token === token && !resets[i].used) {
          if (new Date() > new Date(resets[i].expiresAt))
            return { ok:false, reason:'Token expired' };
          return { ok:true, entry:resets[i] };
        }
      }
      return { ok:false, reason:'Token not found' };
    },

    consume(token) {
      const resets = DB._read('password_resets');
      const i = resets.findIndex(r => r.token === token && !r.used);
      if (i === -1) return false;
      resets[i].used = true; resets[i].usedAt = DB._now();
      DB._write('password_resets', resets);
      return true;
    },
  },

  /* ============================================================
     TABLE 5 — CONTACTS
     From: Add Friends feature
  ============================================================ */
  contacts: {
    getAll() { return DB._read('contacts'); },

    add(userId, contactId) {
      const list = this.getAll();
      if (list.find(c => c.userId === userId && c.contactId === contactId)) return null;
      const entry = {
        id:        DB._id('cnt'),
        userId:    userId,
        contactId: contactId,
        addedAt:   DB._now(),
        status:    'pending',
      };
      list.push(entry); DB._write('contacts', list);
      return entry;
    },

    accept(id) {
      const list = DB._read('contacts');
      const i = list.findIndex(c => c.id === id);
      if (i !== -1) { list[i].status = 'accepted'; DB._write('contacts', list); }
    },

    getByUser(userId) {
      return this.getAll().filter(c => c.userId === userId && c.status === 'accepted');
    },
  },

  /* ============================================================
     TABLE 6 — MESSAGES
     From: Chat message input
  ============================================================ */
  messages: {
    getAll() { return DB._read('messages'); },

    save(data) {
      const msgs = this.getAll();
      const msg = {
        id:         DB._id('msg'),
        chatId:     data.chatId     || '',
        senderId:   data.senderId   || '',
        senderName: data.senderName || '',
        text:       data.text       || '',
        translated: data.translated || '',
        type:       data.type       || 'text',
        status:     'sent',
        sentAt:     DB._now(),
        readAt:     null,
      };
      msgs.push(msg); DB._write('messages', msgs);
      return msg;
    },

    getByChat(chatId)  { return this.getAll().filter(m => m.chatId === chatId); },

    markRead(chatId, readerId) {
      const msgs = DB._read('messages');
      msgs.filter(m => m.chatId === chatId && m.senderId !== readerId)
          .forEach(m => { m.status = 'read'; m.readAt = DB._now(); });
      DB._write('messages', msgs);
    },
  },

  /* ============================================================
     TABLE 7 — NEWSLETTER
     From: Newsletter subscription input
  ============================================================ */
  newsletter: {
    getAll() { return DB._read('newsletter'); },

    subscribe(email) {
      const list = this.getAll();
      if (list.find(n => n.email === email.toLowerCase()))
        return { ok:false, reason:'Already subscribed' };
      const entry = {
        id:           DB._id('nl'),
        email:        email.toLowerCase(),
        subscribedAt: DB._now(),
        isActive:     true,
      };
      list.push(entry); DB._write('newsletter', list);
      DB.activity.log('NEWSLETTER', email + ' subscribed');
      return { ok:true, entry };
    },

    unsubscribe(email) {
      const list = DB._read('newsletter');
      const i = list.findIndex(n => n.email === email.toLowerCase());
      if (i !== -1) { list[i].isActive = false; DB._write('newsletter', list); }
    },
  },

  /* ============================================================
     TABLE 8 — ACTIVITY LOG
     Auto-filled by every DB action
  ============================================================ */
  activity: {
    getAll() { return DB._read('activity'); },

    log(action, detail) {
      const logs = this.getAll();
      logs.push({
        id:        DB._id('act'),
        action:    action,
        detail:    detail,
        timestamp: DB._now(),
        session:   (DB.sessions.getCurrent() || {}).id || 'anonymous',
      });
      if (logs.length > 500) logs.splice(0, logs.length - 500);
      DB._write('activity', logs);
    },

    recent(n) {
      n = n || 20;
      return [...this.getAll()].slice(-n).reverse();
    },
  },
};

/* ---------------------------------------------------------------
   TEMP STORE — multi-step form data (memory only)
--------------------------------------------------------------- */
const FORM_TEMP = {
  loginName:'', loginUsername:'',
  signupName:'', signupEmail:'', signupUsername:'',
  resetEmail:'',
  clear(prefix) {
    Object.keys(this).forEach(k => {
      if (typeof this[k] !== 'function' && k.startsWith(prefix)) this[k] = '';
    });
  },
};

/* ---------------------------------------------------------------
   AUTH HELPERS
--------------------------------------------------------------- */
const Auth = {
  loginOrCreate(name, username, password) {
    let user = DB.users.findByUsername(username);
    if (user) {
      DB.sessions.create(user);
      return { created:false, user: DB.users.safe(user) };
    }
    user = DB.users.create({ name, username, password: btoa(password) });
    DB.sessions.create(user);
    return { created:true, user: DB.users.safe(user) };
  },

  register(name, email, username, password) {
    const user = DB.users.create({
      name, email, username,
      password: btoa(password),
      isVerified: true,
    });
    DB.sessions.create(user);
    return DB.users.safe(user);
  },

  logout() {
    DB.sessions.destroy();
    FORM_TEMP.clear('login');
    FORM_TEMP.clear('signup');
    FORM_TEMP.clear('reset');
  },

  isLoggedIn()   { return DB.sessions.isValid(); },
  currentUser()  {
    const s = DB.sessions.getCurrent();
    return s ? DB.users.safe(DB.users.findById(s.userId)) : null;
  },
};

/* ---------------------------------------------------------------
   FORM HANDLERS
--------------------------------------------------------------- */

/* ---- LOGIN FORM (3 steps) ---- */
function handleLoginStep1(e) {
  e.preventDefault();
  const name = document.getElementById('login-name').value.trim();
  if (!name) { showToast('Error','Please enter your full name','error'); return; }
  FORM_TEMP.loginName = name;
  goToLoginStep(2);
}

function handleLoginStep2(e) {
  e.preventDefault();
  const username = document.getElementById('login-username').value.trim();
  if (!username) { showToast('Error','Please enter a username','error'); return; }
  FORM_TEMP.loginUsername = username;
  goToLoginStep(3);
}

async function handleLoginComplete(e) {
  e.preventDefault();
  const pwd  = document.getElementById('login-password').value;
  const cpwd = document.getElementById('login-confirm-password').value;
  if (pwd.length < 6) { showToast('Error','Password must be at least 6 characters','error'); return; }
  if (pwd !== cpwd)   { showToast('Error','Passwords do not match','error'); return; }

  try {
    const res = await fetch('/api/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: FORM_TEMP.loginName,
        username: FORM_TEMP.loginUsername,
        password: btoa(pwd),
        country: document.getElementById('login-country') ? document.getElementById('login-country').value : 'Pakistan'
      })
    });
    const result = await res.json();
    if (!result.success) {
      showToast('Error', result.message || 'Login failed', 'error');
      return;
    }

    localStorage.setItem('rabta_session_user', JSON.stringify(result.user));
    if (window.setupCurrentUser) {
      window.setupCurrentUser(result.user);
    }

    showToast(
      result.created ? 'Account Created' : 'Welcome Back',
      result.created ? 'ID created for @' + result.user.username + '! Signing you in...'
                     : 'Signed in as ' + result.user.name,
      'success'
    );
    setTimeout(() => navigateTo('chat'), 1000);
    setTimeout(() => {
      e.target.reset();
      document.getElementById('login-name').value     = '';
      document.getElementById('login-username').value = '';
      FORM_TEMP.clear('login');
      goToLoginStep(1);
    }, 1500);
  } catch (err) {
    showToast('Error', 'Server error. Please try again.', 'error');
  }
}

function goToLoginStep(step) {
  [1,2,3].forEach(i =>
    document.getElementById('login-step-container-'+i).style.display = 'none'
  );
  document.getElementById('login-step-container-'+step).style.display = 'block';
  const sub = document.getElementById('login-subtitle');
  if (step===1) sub.textContent = 'Enter your name to begin';
  if (step===2) sub.textContent = 'Choose a unique username';
  if (step===3) sub.textContent = 'Secure your account with a password';
}

/* ---- SIGNUP FORM (4 steps) ---- */
function handleSignupStep1(e) {
  e.preventDefault();
  const name  = document.getElementById('signup-name').value.trim();
  const email = document.getElementById('signup-email').value.trim().toLowerCase();
  if (!name)  { showToast('Error','Please enter your full name','error');    return; }
  if (!email) { showToast('Error','Please enter your email address','error'); return; }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    showToast('Error','Please enter a valid email address','error'); return;
  }
  if (window.GLOBAL_USERS && window.GLOBAL_USERS.some(u => u.email && u.email.toLowerCase() === email)) {
    showToast('Error','This email is already registered. Please sign in.','error'); return;
  }
  FORM_TEMP.signupName  = name;
  FORM_TEMP.signupEmail = email;
  
  // Simulated OTP for simplicity
  const otp = "123456";
  document.getElementById('signup-email-display').textContent = email;
  showToast('OTP Sent','Verification code sent to ' + email + '  |  Use Demo Code: 123456', 'info');
  goToSignupStep(2);
}

function handleSignupStep2(e) {
  e.preventDefault();
  const otp = document.getElementById('signup-otp').value.trim();
  if (!otp) { showToast('Error','Please enter the OTP','error'); return; }
  if (otp === '123456') {
    showToast('Verified','Email verified successfully!','success');
    goToSignupStep(3);
  } else {
    showToast('Error', 'Invalid OTP. Please use the demo code 123456.', 'error');
  }
}

function handleSignupStep3(e) {
  e.preventDefault();
  const username = document.getElementById('signup-username').value.trim().toLowerCase();
  if (!username) { showToast('Error','Please choose a username','error'); return; }
  if (!/^[a-z0-9_]{3,20}$/.test(username)) {
    showToast('Error','3-20 chars: letters, numbers, underscore only','error'); return;
  }
  if (window.GLOBAL_USERS && window.GLOBAL_USERS.some(u => u.username && u.username.toLowerCase() === '@' + username)) {
    showToast('Error','@' + username + ' is taken. Choose another.','error'); return;
  }
  FORM_TEMP.signupUsername = username;
  goToSignupStep(4);
}

async function handleSignupComplete(e) {
  e.preventDefault();
  const pwd  = document.getElementById('signup-password').value;
  const cpwd = document.getElementById('signup-confirm-password').value;
  if (pwd.length < 6) { showToast('Error','Password must be at least 6 characters','error'); return; }
  if (pwd !== cpwd)   { showToast('Error','Passwords do not match','error'); return; }

  try {
    const res = await fetch('/api/signup', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: FORM_TEMP.signupName,
        email: FORM_TEMP.signupEmail,
        username: FORM_TEMP.signupUsername,
        password: btoa(pwd),
        country: document.getElementById('signup-country') ? document.getElementById('signup-country').value : 'Pakistan'
      })
    });
    const result = await res.json();
    if (!result.success) {
      showToast('Error', result.message || 'Signup failed', 'error');
      return;
    }

    localStorage.setItem('rabta_session_user', JSON.stringify(result.user));
    if (window.setupCurrentUser) {
      window.setupCurrentUser(result.user);
    }
    
    showToast('Welcome!','Account created! Welcome, ' + result.user.name + '!','success');
    setTimeout(() => navigateTo('chat'), 1000);
    setTimeout(() => {
      e.target.reset();
      FORM_TEMP.clear('signup');
      goToSignupStep(1);
    }, 1500);
  } catch (err) {
    showToast('Error', 'Server error. Please try again.', 'error');
  }
}

function goToSignupStep(step) {
  for (let i = 1; i <= 4; i++) {
    const el = document.getElementById('signup-step-container-' + i);
    if (el) el.style.display = (i === step) ? 'block' : 'none';
  }
  const sub = document.getElementById('signup-subtitle');
  if (step===1) sub.textContent = 'Enter your details to get started';
  if (step===2) sub.textContent = 'Verify your email address';
  if (step===3) sub.textContent = 'Choose a unique username';
  if (step===4) sub.textContent = 'Secure your account with a password';
}

/* ---- FORGOT PASSWORD FORM ---- */
function handleForgotPassword(e) {
  e.preventDefault();
  const emailEl = e.target.querySelector('input[type="email"]');
  const email   = emailEl ? emailEl.value.trim().toLowerCase() : '';
  if (!email) { showToast('Error','Please enter your email address','error'); return; }
  const reset = DB.passwordResets.create(email);
  showToast('Email Sent','Password reset link sent to ' + email,'success');
  console.log('Reset token (demo): ' + reset.token);
  if (emailEl) emailEl.value = '';
}

/* ---- NEWSLETTER FORM ---- */
function subscribeNewsletter() {
  const el    = document.getElementById('newsletter-email');
  const email = el ? el.value.trim() : '';
  if (!email) { showToast('Error','Please enter a valid email','error'); return; }
  const result = DB.newsletter.subscribe(email);
  if (result.ok) {
    showToast('Subscribed!','You will receive our latest updates','success');
    if (el) el.value = '';
  } else {
    showToast('Already Subscribed','This email is already on our list!','warning');
  }
}

/* ---------------------------------------------------------------
   MAKE GLOBAL
--------------------------------------------------------------- */
window.DB        = DB;
window.Auth      = Auth;
window.FORM_TEMP = FORM_TEMP;

console.log('%c RabtaChat DB loaded. Type DB.inspect() in console to view all tables.',
            'color:#6366f1;font-weight:bold');
