# Custom Domain Setup Guide for Firebase Hosting

## 🎉 Your App is Live!

**Current URL:** https://orgami-66nxok.web.app  
**Firebase Console:** https://console.firebase.google.com/project/orgami-66nxok/hosting

---

## 🌐 Adding a Custom Domain

### Step 1: Access Firebase Console
1. Go to: https://console.firebase.google.com/project/orgami-66nxok/hosting
2. Click **"Add custom domain"**

### Step 2: Enter Your Domain
- Enter your domain name (e.g., `attendus.com` or `app.attendus.com`)
- Click **"Continue"**

### Step 3: Verify Domain Ownership
Firebase will provide you with a TXT record to add to your DNS:

**DNS Record to Add:**
- **Type:** TXT
- **Name:** `@` (or your domain name)
- **Value:** `[Firebase will provide this]`
- **TTL:** 3600 (or default)

### Step 4: Point Domain to Firebase
Add these A records to your DNS:

**A Records:**
- **Type:** A
- **Name:** `@`
- **Value:** `199.36.158.100` (Firebase IP 1)
- **TTL:** 3600

- **Type:** A  
- **Name:** `@`
- **Value:** `199.36.158.101` (Firebase IP 2)
- **TTL:** 3600

**For www subdomain:**
- **Type:** A
- **Name:** `www`
- **Value:** `199.36.158.100`
- **TTL:** 3600

- **Type:** A
- **Name:** `www`  
- **Value:** `199.36.158.101`
- **TTL:** 3600

### Step 5: Wait for SSL Certificate
- Firebase automatically provisions SSL certificates
- This can take up to 24 hours
- Your site will be accessible at `https://yourdomain.com`

---

## 🔧 DNS Provider Examples

### Cloudflare
1. Go to DNS → Records
2. Add A records pointing to Firebase IPs
3. Add TXT record for verification

### GoDaddy
1. Go to DNS Management
2. Add A records with Firebase IPs
3. Add TXT record for verification

### Namecheap
1. Go to Advanced DNS
2. Add A records pointing to Firebase IPs
3. Add TXT record for verification

---

## ⚡ Quick Deploy Commands

**Manual Deploy:**
```bash
flutter clean
flutter build web --release
firebase deploy --only hosting
```

**Automated Deploy:**
```bash
./deploy_web.sh
```

---

## 🛠️ Troubleshooting

### Domain Not Working?
1. **Check DNS Propagation:** Use https://dnschecker.org
2. **Wait Longer:** DNS changes can take 24-48 hours
3. **Check Firebase Console:** Look for any error messages

### SSL Certificate Issues?
- Firebase handles SSL automatically
- Wait up to 24 hours for certificate provisioning
- Check Firebase Console for certificate status

### Common DNS Issues:
- **Wrong IPs:** Make sure you're using Firebase's current IP addresses
- **Missing TXT Record:** Required for domain verification
- **TTL Too High:** Set TTL to 3600 or lower for faster propagation

---

## 📱 Mobile App Integration

Once your domain is set up, you can:

1. **Deep Linking:** Configure your mobile app to open from web links
2. **App Store Links:** Use your domain for app store redirects
3. **Social Sharing:** Share your web app URL

---

## 🎯 Next Steps

1. ✅ **Test your web app** at the Firebase URL
2. ✅ **Add custom domain** following steps above
3. ✅ **Configure mobile deep linking** (optional)
4. ✅ **Set up analytics** (optional)
5. ✅ **Configure CDN** (Firebase handles this automatically)

---

**Need Help?** Check Firebase documentation: https://firebase.google.com/docs/hosting/custom-domain
