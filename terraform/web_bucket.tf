# This file setup GCS bucket that serves webui assets

resource "google_storage_bucket" "webui_bucket" {
  name = trimsuffix(local.domain, ".")

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }
}

resource "google_storage_bucket_iam_binding" "public" {
  bucket = google_storage_bucket.webui_bucket.name
  role = "roles/storage.objectViewer"
  members = [
    "allUsers",
  ]
}
