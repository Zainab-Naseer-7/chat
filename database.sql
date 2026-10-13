-- ================================================================
--  RabtaChat Pro — Complete Database Schema for MySQL/XAMPP
--  File  : database.sql
--  Import: Import this file into XAMPP/phpMyAdmin to create the database
-- ================================================================

CREATE DATABASE IF NOT EXISTS `rabtachat_db` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `rabtachat_db`;

-- ----------------------------------------------------------------
--  TABLE 1 — USERS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `users` (
  `id` VARCHAR(50) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `email` VARCHAR(100) NOT NULL UNIQUE,
  `username` VARCHAR(50) NOT NULL UNIQUE,
  `password` VARCHAR(255) NOT NULL,
  `phone` VARCHAR(20) DEFAULT NULL,
  `avatar` VARCHAR(255) DEFAULT 'U',
  `role` VARCHAR(20) DEFAULT 'user',
  `isVerified` TINYINT(1) DEFAULT 0,
  `isActive` TINYINT(1) DEFAULT 1,
  `createdAt` DATETIME NOT NULL,
  `updatedAt` DATETIME NOT NULL,
  `lastLoginAt` DATETIME DEFAULT NULL,
  `preferences` TEXT DEFAULT NULL, -- JSON string storage for theme, language, etc.
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------
--  TABLE 2 — SESSIONS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `sessions` (
  `id` VARCHAR(50) NOT NULL,
  `userId` VARCHAR(50) NOT NULL,
  `name` VARCHAR(100) DEFAULT NULL,
  `username` VARCHAR(50) DEFAULT NULL,
  `email` VARCHAR(100) DEFAULT NULL,
  `role` VARCHAR(20) DEFAULT NULL,
  `loginAt` DATETIME NOT NULL,
  `expiresAt` DATETIME NOT NULL,
  `device` VARCHAR(255) DEFAULT NULL,
  `isActive` TINYINT(1) DEFAULT 1,
  `logoutAt` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`userId`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------
--  TABLE 3 — OTPs (One-Time Passwords)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `otps` (
  `id` VARCHAR(50) NOT NULL,
  `email` VARCHAR(100) NOT NULL,
  `code` VARCHAR(10) NOT NULL,
  `purpose` VARCHAR(50) DEFAULT 'email_verification',
  `createdAt` DATETIME NOT NULL,
  `expiresAt` DATETIME NOT NULL,
  `used` TINYINT(1) DEFAULT 0,
  `usedAt` DATETIME DEFAULT NULL,
  `attempts` INT DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------
--  TABLE 4 — PASSWORD RESETS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `password_resets` (
  `id` VARCHAR(50) NOT NULL,
  `email` VARCHAR(100) NOT NULL,
  `token` VARCHAR(255) NOT NULL,
  `requestedAt` DATETIME NOT NULL,
  `expiresAt` DATETIME NOT NULL,
  `used` TINYINT(1) DEFAULT 0,
  `usedAt` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------
--  TABLE 5 — CONTACTS
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `contacts` (
  `id` VARCHAR(50) NOT NULL,
  `userId` VARCHAR(50) NOT NULL,
  `contactId` VARCHAR(50) NOT NULL,
  `addedAt` DATETIME NOT NULL,
  `status` VARCHAR(20) DEFAULT 'pending',
  PRIMARY KEY (`id`),
  FOREIGN KEY (`userId`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`contactId`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------
--  TABLE 6 — MESSAGES
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `messages` (
  `id` VARCHAR(50) NOT NULL,
  `chatId` VARCHAR(50) NOT NULL,
  `senderId` VARCHAR(50) NOT NULL,
  `senderName` VARCHAR(100) NOT NULL,
  `text` TEXT NOT NULL,
  `translated` TEXT DEFAULT NULL,
  `type` VARCHAR(20) DEFAULT 'text',
  `status` VARCHAR(20) DEFAULT 'sent',
  `sentAt` DATETIME NOT NULL,
  `readAt` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`senderId`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------
--  TABLE 7 — NEWSLETTER
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `newsletter` (
  `id` VARCHAR(50) NOT NULL,
  `email` VARCHAR(100) NOT NULL UNIQUE,
  `subscribedAt` DATETIME NOT NULL,
  `isActive` TINYINT(1) DEFAULT 1,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------
--  TABLE 8 — ACTIVITY LOG
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `activity_log` (
  `id` VARCHAR(50) NOT NULL,
  `action` VARCHAR(50) NOT NULL,
  `detail` TEXT DEFAULT NULL,
  `timestamp` DATETIME NOT NULL,
  `session` VARCHAR(50) DEFAULT 'anonymous',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
