package fragment

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
)

// S3Config for production write/read via sideweed and HAProxy.
type S3Config struct {
	Bucket           string
	AccessKey        string
	SecretKey        string
	Region           string
	SideweedWriteURL string
	ReadURL          string
}

func defaultS3Config() S3Config {
	return S3Config{
		Bucket:           "video-fragments",
		AccessKey:        "stand_access_key",
		SecretKey:        "stand_secret_key",
		Region:           "us-east-1",
		SideweedWriteURL: "http://localhost:8880",
		ReadURL:          "http://localhost:8882",
	}
}

func (c S3Config) objectURI(bucket, key string) string {
	return fmt.Sprintf("s3://%s/%s", bucket, key)
}

func parseObjectURI(uri string) (bucket, key string, err error) {
	const prefix = "s3://"
	if !strings.HasPrefix(uri, prefix) {
		return "", "", fmt.Errorf("invalid object uri %q", uri)
	}
	rest := strings.TrimPrefix(uri, prefix)
	parts := strings.SplitN(rest, "/", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", fmt.Errorf("invalid object uri %q", uri)
	}
	return parts[0], parts[1], nil
}

func (c S3Config) newS3Client(endpoint string) *s3.S3 {
	endpoint = strings.TrimSuffix(endpoint, "/")
	sess := session.Must(session.NewSession(&aws.Config{
		Region:           aws.String(c.Region),
		Endpoint:         aws.String(endpoint),
		S3ForcePathStyle: aws.Bool(true),
		Credentials:      credentials.NewStaticCredentials(c.AccessKey, c.SecretKey, ""),
		DisableSSL:       aws.Bool(true),
	}))
	return s3.New(sess)
}

func (c S3Config) PutViaSideweed(ctx context.Context, key string, data []byte) (objectURI string, etag string, err error) {
	svc := c.newS3Client(c.SideweedWriteURL)
	out, err := svc.PutObjectWithContext(ctx, &s3.PutObjectInput{
		Bucket: aws.String(c.Bucket),
		Key:    aws.String(key),
		Body:   bytes.NewReader(data),
	})
	if err != nil {
		return "", "", fmt.Errorf("s3 put via sideweed: %w", err)
	}
	if out.ETag != nil {
		etag = strings.Trim(*out.ETag, "\"")
	}
	return c.objectURI(c.Bucket, key), etag, nil
}

func (c S3Config) GetViaReadPath(ctx context.Context, objectURI string) ([]byte, error) {
	bucket, key, err := parseObjectURI(objectURI)
	if err != nil {
		return nil, err
	}
	svc := c.newS3Client(c.ReadURL)
	out, err := svc.GetObjectWithContext(ctx, &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, fmt.Errorf("s3 get via read path: %w", err)
	}
	defer out.Body.Close()
	data, err := io.ReadAll(out.Body)
	if err != nil {
		return nil, err
	}
	return data, nil
}
