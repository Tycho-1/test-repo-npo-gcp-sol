package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"cloud.google.com/go/bigquery"
	"cloud.google.com/go/storage"
)

func main() {
	//
	bucket := "npo_testing_data"
	object := "test_npo"
	file_path := "test.txt"
	uploadFileGCS(bucket, object, file_path)

	projectID := "tycho-project"
	datasetID := "npo"
	tableID := "viewing_events"
	gcs_bucket_link := "gs://npo_testing_data/noisy_mock_events.json"
	importJSONExplicitSchemaBQ(projectID, datasetID, tableID, gcs_bucket_link)

}

func importJSONExplicitSchemaBQ(projectID, datasetID, tableID string, gcs_bucket_link string) error {

	ctx := context.Background()
	client, err := bigquery.NewClient(ctx, projectID)
	if err != nil {
		return fmt.Errorf("bigquery.NewClient: %v", err)
	}
	defer client.Close()

	gcsRef := bigquery.NewGCSReference(gcs_bucket_link)
	gcsRef.SourceFormat = bigquery.JSON
	// gcsRef.Schema = bigquery.Schema{
	// 	{Name: "UserId", Type: bigquery.IntegerFieldType},
	// 	{Name: "EventType", Type: bigquery.StringFieldType},
	// 	{Name: "DateTime", Type: bigquery.TimestampFieldType},  // to do add more
	// }
	gcsRef.AutoDetect = true
	loader := client.Dataset(datasetID).Table(tableID).LoaderFrom(gcsRef)
	// loader.TimePartitioning = &bigquery.TimePartitioning{
	// 	Field: "DateTime",
	// 	Type:  "DAY",
	// 	// Expiration: 90 * 24 * time.Hour,
	// }

	loader.WriteDisposition = bigquery.WriteTruncate // to be changed to WriteAppend for normal use

	job, err := loader.Run(ctx)
	if err != nil {
		fmt.Println(err)
		return err
	}
	status, err := job.Wait(ctx)
	if err != nil {
		fmt.Println(err)
		return err
	}

	if status.Err() != nil {
		return fmt.Errorf("job completed with error: %v", status.Err())
	}
	if status.Err() == nil {
		fmt.Println("Loaded data")
	}

	return nil
}

// uploadFile uploads an object.
func uploadFileGCS(bucket, object string, file_path string) error { //w io.Writer,

	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		return fmt.Errorf("storage.NewClient: %w", err)
	}
	defer client.Close()

	// Open local file.
	f, err := os.Open(file_path)
	if err != nil {
		return fmt.Errorf("os.Open: %w", err)
	}
	defer f.Close()

	ctx, cancel := context.WithTimeout(ctx, time.Second*50)
	defer cancel()

	o := client.Bucket(bucket).Object(object)

	// Optional: set a generation-match precondition to avoid potential race
	// conditions and data corruptions. The request to upload is aborted if the
	// object's generation number does not match your precondition.
	// For an object that does not yet exist, set the DoesNotExist precondition.
	o = o.If(storage.Conditions{DoesNotExist: true})
	// If the live object already exists in your bucket, set instead a
	// generation-match precondition using the live object's generation number.
	// attrs, err := o.Attrs(ctx)
	// if err != nil {
	//      return fmt.Errorf("object.Attrs: %w", err)
	// }
	// o = o.If(storage.Conditions{GenerationMatch: attrs.Generation})

	// Upload an object with storage.Writer.
	wc := o.NewWriter(ctx)
	if _, err = io.Copy(wc, f); err != nil {
		return fmt.Errorf("io.Copy: %w", err)
	}
	if err == nil {
		fmt.Println("Uploaded the file!")
	}
	if err := wc.Close(); err != nil {
		return fmt.Errorf("Writer.Close: %w", err)
	}
	// fmt.Fprintf(w, "Blob %v uploaded.\n", object)

	return nil
}
