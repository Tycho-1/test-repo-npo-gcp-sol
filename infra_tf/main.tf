terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

resource "google_bigquery_dataset" "npo_viewing_data" {
  dataset_id                  = "npo"
  friendly_name               = "test"
  description                 = "Testing viewing events"
  location                    = "EU"
 // default_table_expiration_ms = 3600000

  labels = {
    env = "staging"
  }
}


resource "google_bigquery_table" "viewing_events" {
  dataset_id = google_bigquery_dataset.npo_viewing_data.dataset_id
  table_id   = "viewing_events"

  deletion_protection = false

  time_partitioning {
    type = "DAY"
    field = "DateTime"
  }

  labels = {
    env = "staging"
  }

  schema = <<EOF
[
  {
    "name": "EventId",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "A unique identifier for this event in the form of a SHA256 hash"
  },
  {
    "name": "MediaId",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "A unique identifier for watched Media items as an integer"
  },
  {
    "name": "UserId",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "A unique identifier for a user-account as an integer"
  },
  {
    "name": "Timestamp",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "A Unix/POSIX Epoch time representation of the client-side time"
  },
  {
    "name": "DateTime",
    "type": "TIMESTAMP",
    "mode": "NULLABLE",
    "description": "An ISO-8601 formatted representation of the client-side time"
  },
  {
    "name": "EventType",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "The type of view-event send to the server"
  }
]
EOF

}


resource "google_bigquery_table" "view1" {
  dataset_id = google_bigquery_dataset.npo_viewing_data.dataset_id
  table_id   = "viewing_events_agg_per_day"
  deletion_protection = false

  labels = {
    env = "staging"
  }

  view { 
    query =   " SELECT extract(DATE from DateTime) Date, count(EventId) Nr_events, extract(DAYOFWEEK FROM DateTime) Dayofweek, extract(WEEK FROM DateTime) Week, ROUND(count(EventId)/2/60,2) as Est_approx_hours, COUNT(DISTINCT UserId) as Nr_of_users FROM `tycho-project.npo.viewing_events` where EventType = \"waypoint\"  group by extract(DATE from DateTime), Week, Dayofweek order by Date asc;  "
     use_legacy_sql = false
  }
}

resource "google_bigquery_table" "view2" {
  dataset_id = google_bigquery_dataset.npo_viewing_data.dataset_id
  table_id   = "viewing_events_agg_per_hour"
  deletion_protection = false

  labels = {
    env = "staging"
  }

  view { 
    query =   "SELECT extract(DATE from DateTime) Date, EXTRACT(HOUR FROM(TIME(DateTime))) as Hour, count(EventId) nr_events, extract(DAYOFWEEK FROM DateTime) Dayofweek, extract(WEEK FROM DateTime) Week, COUNT(DISTINCT UserId) as Nr_of_users  FROM `tycho-project.npo.viewing_events` where EventType = \"waypoint\"  group by Date, Hour, EventType, Week, Dayofweek  order by Date asc, Hour; "
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "view3" {
  dataset_id = google_bigquery_dataset.npo_viewing_data.dataset_id
  table_id   = "viewing_events_agg_per_user"
  deletion_protection = false

  labels = {
    env = "staging"
  }

  view { 
    query =   " SELECT UserId, count(DISTINCT MediaId) nr_videos, count(EventId) nr_events, extract(WEEK FROM DateTime) Week, extract(YEAR from DateTime) Year, ROUND(count(EventId)/2/count(DISTINCT MediaId), 2) as ApproxMinPerVideo  FROM `tycho-project.npo.viewing_events` where EventType = \"waypoint\"  group by Week, UserId, Year  order by UserId asc, Year asc, Week; "
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "view4" {
  dataset_id = google_bigquery_dataset.npo_viewing_data.dataset_id
  table_id   = "viewing_events_agg_per_media"
  deletion_protection = false

  labels = {
    env = "staging"
  }

  view { 
    query =  "SELECT MediaId,  count(EventId) nr_events,  COUNT(DISTINCT UserId) as cnt_nr_users, COUNT(DISTINCT (extract(DATE from DateTime))) as cnt_nr_days, ROUND(count(EventId)/2/60,2) as Est_approx_hours FROM `tycho-project.npo.viewing_events` WHERE EventType = \"waypoint\" GROUP BY MediaId,EventType order by nr_events desc; "
    use_legacy_sql = false
  }
}

resource "google_storage_bucket" "npo_test_data" {
  name          = "npo_testing_data"
  location      = "EU"
  force_destroy = true

  uniform_bucket_level_access = true


}

resource "google_storage_bucket_object" "main_data" {
  name   = "noisy_mock_events.json"
  source = "/home/tycho/Documents/job_application_folder/npo_data_eng_application/noisy_mock_events_edited.json"
  bucket = "npo_testing_data"
 // it took 30 min to load the 2.5Gb file 
}


resource "google_cloud_run_v2_job" "cloudrunjob1" {
  name     = "bq-load-json"
  location = var.region
  provider = google-beta

  template {
    template {
      containers {
        image = "europe-west1-docker.pkg.dev/tycho-project/cloud-run-source-deploy/bq-load-json:v1.0.0"

        volume_mounts {
          name       = "gcs1"
          mount_path = "/mnt/my-vol"
        }
      }
      volumes {
        name = "gcs1"
        gcs {
          bucket = "npo_testing_data"
        }
      }
    }

  }
}






resource "google_bigquery_routine" "routine_media" {
  dataset_id      = google_bigquery_dataset.npo_viewing_data.dataset_id
  routine_id      = "viewing_events_agg_media_param_dt"
  routine_type    = "TABLE_VALUED_FUNCTION"
  language        = "SQL"
  definition_body = <<-EOS
        SELECT MediaId, count(EventId) nr_events, COUNT(DISTINCT UserId) as cnt_nr_users,
        COUNT(DISTINCT (extract(DATE from DateTime))) as cnt_nr_days,
        ROUND(count(EventId)/2/60,2) as Est_approx_hours
        FROM ( 
          SELECT * FROM `tycho-project.npo.viewing_events` 
              WHERE DateTime > TIMESTAMP(start) and DateTime < TIMESTAMP(ends)
            )
        WHERE EventType = "waypoint" 
        GROUP BY MediaId,EventType order by nr_events desc   
  EOS
  arguments {
    name      = "start"
    data_type = jsonencode({ "typeKind" : "STRING" })
  }
  arguments {
    name      = "ends"
    data_type = jsonencode({ "typeKind" : "STRING" })
  }

}



resource "google_bigquery_routine" "routine_day" {
  dataset_id      = google_bigquery_dataset.npo_viewing_data.dataset_id
  routine_id      = "viewing_events_agg_day_param_dt"
  routine_type    = "TABLE_VALUED_FUNCTION"
  language        = "SQL"
  definition_body = <<-EOS
        SELECT extract(DATE from DateTime) Date, count(EventId) Nr_events, 
        extract(DAYOFWEEK FROM DateTime) Dayofweek, extract(WEEK FROM DateTime) Week,
        ROUND(count(EventId)/2/60,2) as Est_approx_hours, 
        COUNT(DISTINCT UserId) as Nr_of_users          
        FROM ( 
          SELECT * FROM `tycho-project.npo.viewing_events` 
              WHERE DateTime > TIMESTAMP(start) and DateTime < TIMESTAMP(ends)
            )
        where EventType = "waypoint"  
        group by extract(DATE from DateTime), Week, Dayofweek 
        order by Date asc

  EOS
  arguments {
    name      = "start"
    data_type = jsonencode({ "typeKind" : "STRING" })
  }
  arguments {
    name      = "ends"
    data_type = jsonencode({ "typeKind" : "STRING" })
  }

}



resource "google_bigquery_routine" "routine_hour" {
  dataset_id      = google_bigquery_dataset.npo_viewing_data.dataset_id
  routine_id      = "viewing_events_agg_hour_param_dt"
  routine_type    = "TABLE_VALUED_FUNCTION"
  language        = "SQL"
  definition_body = <<-EOS
        SELECT extract(DATE from DateTime) Date, EXTRACT(HOUR FROM(TIME(DateTime))) as Hour, 
        count(EventId) nr_events, extract(DAYOFWEEK FROM DateTime) Dayofweek, 
        extract(WEEK FROM DateTime) Week, COUNT(DISTINCT UserId) as Nr_of_users        
        FROM ( 
          SELECT * FROM `tycho-project.npo.viewing_events` 
              WHERE DateTime > TIMESTAMP(start) and DateTime < TIMESTAMP(ends)
            )
        where EventType = "waypoint"  
        group by Date, Hour, EventType, Week, Dayofweek  
        order by Date asc, Hour
  EOS
  arguments {
    name      = "start"
    data_type = jsonencode({ "typeKind" : "STRING" })
  }
  arguments {
    name      = "ends"
    data_type = jsonencode({ "typeKind" : "STRING" })
  }

}



resource "google_bigquery_routine" "routine_user" {
  dataset_id      = google_bigquery_dataset.npo_viewing_data.dataset_id
  routine_id      = "viewing_events_agg_user_param_dt"
  routine_type    = "TABLE_VALUED_FUNCTION"
  language        = "SQL"
  definition_body = <<-EOS
        SELECT UserId, count(DISTINCT MediaId) nr_videos, count(EventId) nr_events, 
        extract(WEEK FROM DateTime) Week, extract(YEAR from DateTime) Year, 
        ROUND(count(EventId)/2/count(DISTINCT MediaId), 2) as ApproxMinPerVideo       
        FROM ( 
          SELECT * FROM `tycho-project.npo.viewing_events` 
              WHERE DateTime > TIMESTAMP(start) and DateTime < TIMESTAMP(ends)
            )
        where EventType = "waypoint"  
        group by Week, UserId, Year  
        order by UserId asc, Year asc, Week

  EOS
  arguments {
    name      = "start"
    data_type = jsonencode({ "typeKind" : "STRING" })
  }
  arguments {
    name      = "ends"
    data_type = jsonencode({ "typeKind" : "STRING" })
  }

}
