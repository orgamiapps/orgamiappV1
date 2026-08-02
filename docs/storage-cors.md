# Firebase Storage CORS

Attendus event images are served from the Firebase Storage bucket
`orgami-66nxok.appspot.com`. The checked-in policy allows the production web
origins, Firebase Hosting origins, and local development origins to read image
responses.

Apply the policy from the repository root:

```powershell
gcloud storage buckets update gs://orgami-66nxok.appspot.com --cors-file=firebase/storage-cors.json
```

Verify it without printing any Firebase download token:

```powershell
gcloud storage buckets describe gs://orgami-66nxok.appspot.com --format="json(cors_config)"
```

When the image-delivery policy changes, also increment
`attendusEventImageCacheVersion` in
`lib/widgets/attendus_design_system.dart`. This forces browsers to request a
fresh response while leaving the original Firestore image URL unchanged.
