// Spellmind's identity: the names the app, its key store entries and its installer go by.
// Its own, so Spellmind never shares saved keys or sign-ins with NeverQuestAlone or another app
// built from the same code (Windows Credential Manager and the Secret Service don't keep apps apart:
// keychainService is what does).
export const IDENTITY = Object.freeze({
  appId: 'gg.spellmind.app',
  productName: 'Spellmind',
  name: 'spellmind',
  keychainService: 'Spellmind',
  copyright: 'Copyright © 2026 The Spellmind authors (MIT)',
});
