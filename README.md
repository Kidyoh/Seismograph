# Seismograph

Your phone as a seismograph. While it charges overnight on the nightstand, the
app listens to the accelerometer for earthquake-like shaking. Phones across
the city report what they feel, and a Cloud Function confirms a tremor when
enough of them feel it at the same moment.

Android only. iOS doesn't allow continuous background accelerometer access.

```
app/         Flutter app (Android)
functions/   Firebase Cloud Function that correlates detections
firestore.rules, firestore.indexes.json, firebase.json
```

## How it works

### On the phone

1. **Gate.** A foreground service stays idle until the phone is plugged in
   and, by default, inside the night window (22:00–07:00). Doze never kicks in
   while charging, so the service can sample all night without battery cost.
   Turning off **Only while charging** lets it listen on battery too: it asks
   for a battery-optimization exemption so Android keeps the sensor running,
   and it pauses below 20 % charge.
2. **Detector** (`app/lib/src/detection/detector.dart`), at 50 Hz:
   - band-passes each axis to 0.5–15 Hz, which drops gravity and slow tilt;
   - runs a classic **STA/LTA** trigger (1 s short-term over 30 s long-term
     energy), the same method seismic networks use;
   - also needs real amplitude behind the ratio, so a very quiet sensor
     doesn't trigger on its own noise;
   - watches 2 s after onset and **rejects knocks and footsteps**, whose
     energy dies out in a fraction of a second, and **rejects handling**
     (a peak over 4 m/s²);
   - tracks gravity and **restarts if the phone is tilted** more than 3°,
     which means someone picked it up;
   - reports **too noisy** instead of guessing when the background is loud,
     like a phone on a bed or near a washing machine.
3. **Report.** Each detection is saved locally and, if sharing is on, written
   to Firestore along with a location rounded to about 1 km. A heartbeat every
   10 minutes tells the backend the phone is listening.

### In the cloud

`onTriggerCreated` runs for every detection:

- finds other phones' triggers within **30 s and 50 km**, counting one per phone;
- counts phones that were **listening** nearby, using their heartbeats;
- confirms when at least **3 phones** triggered **and** they make up at least
  **15 %** of the listeners nearby, so one busy street in a dense area can't
  confirm a quake alone;
- writes or updates `events/{id}`. All the phones see that collection.

Other safeguards: a phone that triggers more than 6 times an hour is ignored,
phones can't read each other's triggers, and simulated detections never mix
with real ones. You can tune the thresholds at deploy time with the
`MIN_DEVICES`, `MIN_PERCENT` and `RADIUS_KM` params.

## Running it

### App only (no backend)

```sh
cd app
flutter run
```

Without Firebase config, the app runs offline: detection, the live trace and
local history all work, and the network section explains what's missing.

### With Firebase

1. Create a Firebase project. Enable **Anonymous** sign-in and **Firestore**.
2. Add an Android app with package `io.github.kidyoh.seismograph`, download
   `google-services.json`, and put it in `app/android/app/`. It's gitignored,
   and the Google Services Gradle plugin is applied only when the file exists.
3. Deploy the rules, indexes and TTL policies, and the function:
   ```sh
   firebase use --add
   cd functions && npm install && cd ..
   firebase deploy --only firestore,functions
   ```
   The TTL policies on `devices.expireAt` and `triggers.expireAt` come from
   `fieldOverrides` in `firestore.indexes.json`, and can take a while to
   become active.
4. `cd app && flutter run`

### Trying it without an earthquake

Settings → **Simulate a tremor** feeds 5 s of synthetic 3 Hz shaking into the
live sensor stream, so it runs through the real detector and upload path.
These detections are marked `test` and only cluster with other test
detections. Do it on three phones within 30 s to see a TEST event confirmed.

Local emulators: `cd functions && npm run serve`.

## Tests

```sh
cd app && flutter test        # detector, gating, geo helpers
cd functions && npm test      # clustering and decision logic
```

## Privacy

- Anonymous auth only. No account, no name. The app signs in anonymously
  whenever Firebase is configured, even with **Share detections** off, so it
  can show confirmed events. With sharing off it uploads nothing, apart from
  one last heartbeat when you switch sharing off that marks the phone as no
  longer listening.
- Coarse location permission only, rounded again to two decimals (about 1 km)
  before it's stored or sent.
- The location is fetched only when you turn monitoring on without one set,
  or tap **Update** in Settings. The background service never asks for it.
- Phones can't read each other's detections or heartbeats; they only see
  confirmed events, which hold an averaged location and phone counts but no
  phone ids.
- **Retention.** Every heartbeat and detection carries an `expireAt` time,
  and Firestore TTL policies delete them after it: a phone's heartbeat 7 days
  after its latest one, a detection 30 days after it happened. The rules
  reject uploads without an expiry or with one further out than that (plus a
  day for clock skew). TTL deletion usually happens within a day of expiry.
  Confirmed events are kept.
- **Deleting your data.** Settings → **Delete my uploaded data** deletes this
  phone's heartbeat and every detection it uploaded. The rules let a phone
  read and delete only documents under its own anonymous id. Turn off
  **Share detections** first if you don't want new data uploaded afterwards.
  The id lives on the phone, so after uninstalling or clearing app data your
  old uploads can't be deleted from the app; they expire as above.

## Limitations and next steps

- It's an experiment, not a warning system.
- Phones on furniture overstate ground motion, so the MMI shown is a rough guess.
- Next steps: push notifications through FCM for confirmed events; Firebase
  App Check to block forged triggers; an on-device classifier like MyShake's
  to replace the hand-tuned impulse and handling rules; and locating the
  epicentre from arrival times instead of using the centroid.
