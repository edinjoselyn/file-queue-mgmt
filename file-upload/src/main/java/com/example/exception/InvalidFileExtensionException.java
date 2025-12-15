package com.example.exception;

public class InvalidFileExtensionException extends Exception {
    public InvalidFileExtensionException(String message) {
        super(message);
    }

    public InvalidFileExtensionException(String message, Throwable throwable) {
        super(message, throwable);
    }
}
