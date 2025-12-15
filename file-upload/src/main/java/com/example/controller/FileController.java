package com.example.controller;

import com.example.exception.InvalidFileExtensionException;
import io.micrometer.common.util.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.core.sync.RequestBody;

import java.io.IOException;

@RestController
@RequestMapping("/api")
public class FileController {

    private final S3Client s3Client;
    private static final String bucketName = "edin-bucket-523919781340";
    private static final Logger logger = LoggerFactory.getLogger(FileController.class);

    public FileController(S3Client s3Client) {
        this.s3Client = s3Client;
    }

    @PostMapping("/upload")
    public ResponseEntity<String> uploadFile(@RequestParam("file") MultipartFile file) throws InvalidFileExtensionException {
        String keyName = file.getOriginalFilename();
        logger.info("event=StartedFileUpload fileName={} bucketName={}", keyName, bucketName);
        try {
            if (StringUtils.isBlank(keyName) || !keyName.contains(".pdf")) {
                throw new InvalidFileExtensionException("Invalid File Extension");
            }
            s3Client.putObject(
                    PutObjectRequest.builder()
                            .bucket(bucketName)
                            .key(keyName)
                            .build(),
                    RequestBody.fromBytes(file.getBytes())
            );
            logger.info("event=CompletedFileUpload fileName={} bucketName={}", keyName, bucketName);
        } catch (IOException e) {
            logger.error("event=IOExceptionOccurred fileName={} bucketName={}", keyName, bucketName);
            return ResponseEntity.status(500).body("Failed to read file");
        } catch (InvalidFileExtensionException e) {
            logger.error("event=InvalidFileExtensionException fileName={} bucketName={}", keyName, bucketName);
            return ResponseEntity.status(500).body("Failed to read file");
        } catch (Exception e) {
            logger.error("event=ExceptionOccurred fileName={} bucketName={}", keyName, bucketName);
            return ResponseEntity.status(500).body("Failed to upload to S3: " + e.getMessage());
        }
        return ResponseEntity.ok("File uploaded: " + keyName);
    }
}
