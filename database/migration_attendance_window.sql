-- Adds check-in / check-out time windows to settings

ALTER TABLE settings ADD COLUMN IF NOT EXISTS
  checkin_window_start TIME DEFAULT '08:45:00';

ALTER TABLE settings ADD COLUMN IF NOT EXISTS
  checkin_window_end TIME DEFAULT '10:00:00';

ALTER TABLE settings ADD COLUMN IF NOT EXISTS
  checkout_window_start TIME DEFAULT '17:00:00';

ALTER TABLE settings ADD COLUMN IF NOT EXISTS
  checkout_window_end TIME DEFAULT '19:00:00';
