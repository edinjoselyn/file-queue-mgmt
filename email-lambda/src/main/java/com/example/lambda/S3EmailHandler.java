package com.example.lambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.ses.SesClient;
import software.amazon.awssdk.services.ses.model.*;

import java.net.URL;
import java.time.Duration;

public class S3EmailHandler implements RequestHandler<SQSEvent, String> {

    private final SesClient ses = SesClient.create();
    private final S3Presigner presigner = S3Presigner.create();
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static final String FROM_EMAIL = "edin.joselyn@gmail.com";
    private static final String TO_EMAIL = "edin.joselyn@gmail.com";

    @Override
    public String handleRequest(SQSEvent event, Context context) {
        for (SQSEvent.SQSMessage msg : event.getRecords()) {
            try {
                context.getLogger().log("Message Body: " + msg.getBody());

                // Parse S3 event JSON inside the SQS message
                JsonNode root = MAPPER.readTree(msg.getBody());
                JsonNode s3Event = root.path("Records").get(0).path("s3");
                String bucket = s3Event.path("bucket").path("name").asText();
                String key = s3Event.path("object").path("key").asText();

                // Generate pre-signed URL valid for 1 hour
                GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                        .bucket(bucket)
                        .key(key)
                        .build();

                GetObjectPresignRequest presignRequest = GetObjectPresignRequest.builder()
                        .signatureDuration(Duration.ofHours(1))
                        .getObjectRequest(getObjectRequest)
                        .build();

                URL presignedUrl = presigner.presignGetObject(presignRequest).url();

                // Build email
                String subject = "📂 New file uploaded to S3";
                String body = "A new file has been uploaded to S3.\n\n" +
                        "Bucket: " + bucket + "\n" +
                        "Key: " + key + "\n\n" +
                        "Download link (valid 1 hour):\n" + presignedUrl + "\n";

                SendEmailRequest emailRequest = SendEmailRequest.builder()
                        .source(FROM_EMAIL)
                        .destination(Destination.builder().toAddresses(TO_EMAIL).build())
                        .message(Message.builder()
                                .subject(Content.builder().data(subject).build())
                                .body(Body.builder()
                                        .text(Content.builder().data(body).build())
                                        .build())
                                .build())
                        .build();

                ses.sendEmail(emailRequest);

                context.getLogger().log("✅ Email sent for file: " + key);

            } catch (Exception e) {
                context.getLogger().log("❌ Error processing SQS message: " + e.getMessage());
            }
        }
        return "done";
    }
}

