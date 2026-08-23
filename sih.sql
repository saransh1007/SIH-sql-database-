

CREATE DATABASE IF NOT EXISTS SIH_AYUSH
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE SIH_AYUSH;

CREATE TABLE IF NOT EXISTS patients (
    patient_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    registration_id     VARCHAR(20) NULL,
    phone               VARCHAR(10) NOT NULL COMMENT 'Store digits only, e.g. 9876543210',
    full_name           VARCHAR(120) NULL,
    date_of_birth       DATE NULL,
    gender              ENUM('FEMALE','MALE','OTHER','PREFER_NOT_TO_SAY') NULL,
    address             VARCHAR(500) NULL,
    emergency_contact   VARCHAR(15) NULL,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (patient_id),
    UNIQUE KEY uq_patients_registration_id (registration_id),
    UNIQUE KEY uq_patients_phone (phone),
    CONSTRAINT chk_patient_phone_digits CHECK (phone REGEXP '^[0-9]{10,15}$')
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS doctors (
    doctor_id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    doctor_code         VARCHAR(30) NOT NULL,
    full_name           VARCHAR(120) NOT NULL,
    speciality          VARCHAR(120) NULL,
    phone               VARCHAR(15) NULL,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (doctor_id),
    UNIQUE KEY uq_doctors_code (doctor_code),
    CONSTRAINT chk_doctor_phone_digits CHECK (phone IS NULL OR phone REGEXP '^[0-9]{10,15}$')
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS patient_medical_history (
    history_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    patient_id          BIGINT UNSIGNED NOT NULL,
    history_type        ENUM('CONDITION','SURGERY','FAMILY_HISTORY','LIFESTYLE','OTHER') NOT NULL,
    title               VARCHAR(150) NOT NULL COMMENT 'Example: Diabetes, appendix surgery',
    details             TEXT NULL,
    diagnosed_on        DATE NULL,
    is_current          BOOLEAN NOT NULL DEFAULT TRUE,
    recorded_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (history_id),
    KEY idx_history_patient_current (patient_id, is_current),
    CONSTRAINT fk_history_patient FOREIGN KEY (patient_id)
        REFERENCES patients(patient_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS patient_allergies (
    allergy_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    patient_id          BIGINT UNSIGNED NOT NULL,
    allergen            VARCHAR(150) NOT NULL,
    reaction_details    VARCHAR(500) NULL,
    severity            ENUM('MILD','MODERATE','SEVERE','UNKNOWN') NOT NULL DEFAULT 'UNKNOWN',
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    recorded_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (allergy_id),
    UNIQUE KEY uq_patient_allergen (patient_id, allergen),
    CONSTRAINT fk_allergy_patient FOREIGN KEY (patient_id)
        REFERENCES patients(patient_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS daily_token_counter (
    token_date          DATE NOT NULL,
    last_token          INT UNSIGNED NOT NULL,
    PRIMARY KEY (token_date)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS visits (
    visit_id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    patient_id          BIGINT UNSIGNED NOT NULL,
    doctor_id           BIGINT UNSIGNED NULL,
    visit_date          DATE NOT NULL,
    token_number        INT UNSIGNED NOT NULL,
    token_code          VARCHAR(30) NOT NULL COMMENT 'Example: AYU-20260823-001',
    status              ENUM('WAITING','IN_CONSULTATION','COMPLETED','CANCELLED') NOT NULL DEFAULT 'WAITING',
    symptom_language    VARCHAR(20) NOT NULL DEFAULT 'Hindi',
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    checked_in_at       DATETIME NULL,
    completed_at        DATETIME NULL,
    PRIMARY KEY (visit_id),
    UNIQUE KEY uq_visit_token_per_day (visit_date, token_number),
    UNIQUE KEY uq_visit_token_code (token_code),
    KEY idx_visits_patient_date (patient_id, visit_date DESC),
    KEY idx_visits_doctor_status_date (doctor_id, status, visit_date),
    CONSTRAINT fk_visit_patient FOREIGN KEY (patient_id)
        REFERENCES patients(patient_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_visit_doctor FOREIGN KEY (doctor_id)
        REFERENCES doctors(doctor_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS visit_symptoms (
    symptom_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    visit_id            BIGINT UNSIGNED NOT NULL,
    input_method        ENUM('TYPED','VOICE_TRANSCRIPT','DOCTOR_ADDED') NOT NULL,
    symptom_text        TEXT NOT NULL,
    recorded_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (symptom_id),
    KEY idx_symptoms_visit (visit_id),
    CONSTRAINT fk_symptom_visit FOREIGN KEY (visit_id)
        REFERENCES visits(visit_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS prescription_uploads (
    upload_id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    patient_id          BIGINT UNSIGNED NOT NULL,
    visit_id            BIGINT UNSIGNED NULL,
    original_filename   VARCHAR(255) NOT NULL,
    storage_path        VARCHAR(500) NOT NULL COMMENT 'Path/key returned by Python after saving file',
    mime_type           VARCHAR(100) NOT NULL,
    file_size_bytes     BIGINT UNSIGNED NOT NULL,
    uploaded_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (upload_id),
    KEY idx_uploads_patient_date (patient_id, uploaded_at DESC),
    KEY idx_uploads_visit (visit_id),
    CONSTRAINT chk_upload_type CHECK (mime_type IN ('application/pdf','image/jpeg','image/png')),
    CONSTRAINT chk_upload_max_size CHECK (file_size_bytes <= 10485760),
    CONSTRAINT fk_upload_patient FOREIGN KEY (patient_id)
        REFERENCES patients(patient_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_upload_visit FOREIGN KEY (visit_id)
        REFERENCES visits(visit_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS consultation_summaries (
    summary_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    visit_id            BIGINT UNSIGNED NOT NULL,
    illness_summary     TEXT NOT NULL,
    diagnosis           VARCHAR(500) NULL,
    treatment_plan      TEXT NULL,
    follow_up_on        DATE NULL,
    reviewed_by_doctor  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (summary_id),
    UNIQUE KEY uq_summary_visit (visit_id),
    CONSTRAINT fk_summary_visit FOREIGN KEY (visit_id)
        REFERENCES visits(visit_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;


CREATE OR REPLACE VIEW vw_doctor_patient_search AS
SELECT
    p.patient_id, p.registration_id, p.phone, p.full_name, p.date_of_birth,
    p.gender, p.is_active,
    MAX(v.created_at) AS latest_submission_at,
    MAX(v.visit_date) AS latest_visit_date,
    COUNT(v.visit_id) AS total_visits
FROM patients AS p
LEFT JOIN visits AS v ON v.patient_id = p.patient_id
GROUP BY p.patient_id, p.registration_id, p.phone, p.full_name,
         p.date_of_birth, p.gender, p.is_active;

CREATE OR REPLACE VIEW vw_waiting_tokens AS
SELECT
    v.visit_id, v.visit_date, v.token_number, v.token_code, v.created_at,
    p.patient_id, p.registration_id, p.full_name, p.phone,
    d.full_name AS doctor_name
FROM visits AS v
JOIN patients AS p ON p.patient_id = v.patient_id
LEFT JOIN doctors AS d ON d.doctor_id = v.doctor_id
WHERE v.status = 'WAITING';

CREATE OR REPLACE VIEW vw_patient_timeline AS
SELECT
    p.patient_id, p.registration_id, p.full_name, p.phone,
    v.visit_id, v.visit_date, v.token_code, v.status,
    GROUP_CONCAT(CONCAT(s.input_method, ': ', s.symptom_text)
                 ORDER BY s.recorded_at SEPARATOR '\n') AS submitted_symptoms,
    cs.illness_summary, cs.diagnosis, cs.treatment_plan, cs.follow_up_on
FROM patients AS p
JOIN visits AS v ON v.patient_id = p.patient_id
LEFT JOIN visit_symptoms AS s ON s.visit_id = v.visit_id
LEFT JOIN consultation_summaries AS cs ON cs.visit_id = v.visit_id
GROUP BY p.patient_id, p.registration_id, p.full_name, p.phone,
         v.visit_id, v.visit_date, v.token_code, v.status,
         cs.illness_summary, cs.diagnosis, cs.treatment_plan, cs.
  
DELIMITER $$

CREATE PROCEDURE sp_submit_patient_visit(
    IN  p_phone VARCHAR(15),
    IN  p_full_name VARCHAR(120),
    IN  p_date_of_birth DATE,
    IN  p_gender VARCHAR(20),
    IN  p_symptom_text TEXT,
    IN  p_input_method VARCHAR(20),
    IN  p_language VARCHAR(20),
    OUT o_patient_id BIGINT,
    OUT o_registration_id VARCHAR(20),
    OUT o_visit_id BIGINT,
    OUT o_token_code VARCHAR(30)
)
BEGIN
    DECLARE v_patient_id BIGINT UNSIGNED;
    DECLARE v_token_number INT UNSIGNED;

    IF p_phone IS NULL OR p_phone NOT REGEXP '^[0-9]{10,15}$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Phone must contain 10 to 15 digits only';
    END IF;
    IF p_symptom_text IS NULL OR CHAR_LENGTH(TRIM(p_symptom_text)) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Symptoms cannot be empty';
    END IF;
    IF p_input_method NOT IN ('TYPED','VOICE_TRANSCRIPT') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Input method must be TYPED or VOICE_TRANSCRIPT';
    END IF;

    START TRANSACTION;

    SELECT patient_id INTO v_patient_id
    FROM patients WHERE phone = p_phone FOR UPDATE;

    IF v_patient_id IS NULL THEN
        INSERT INTO patients (phone, full_name, date_of_birth, gender)
        VALUES (p_phone, NULLIF(TRIM(p_full_name), ''), p_date_of_birth,
                CASE WHEN p_gender IN ('FEMALE','MALE','OTHER','PREFER_NOT_TO_SAY') THEN p_gender ELSE NULL END);
        SET v_patient_id = LAST_INSERT_ID();
        UPDATE patients
        SET registration_id = CONCAT('AYU-', LPAD(v_patient_id, 8, '0'))
        WHERE patient_id = v_patient_id;
    END IF;

    -- Atomic counter: safe even if more users arrive at the same time.
    INSERT INTO daily_token_counter (token_date, last_token)
    VALUES (CURDATE(), 1)
    ON DUPLICATE KEY UPDATE last_token = LAST_INSERT_ID(last_token + 1);

    IF ROW_COUNT() = 1 THEN
        SET v_token_number = 1;
    ELSE
        SET v_token_number = LAST_INSERT_ID();
    END IF;

    SET o_token_code = CONCAT('AYU-', DATE_FORMAT(CURDATE(), '%Y%m%d'), '-', LPAD(v_token_number, 3, '0'));

    INSERT INTO visits (patient_id, visit_date, token_number, token_code, symptom_language)
    VALUES (v_patient_id, CURDATE(), v_token_number, o_token_code, COALESCE(NULLIF(TRIM(p_language), ''), 'Hindi'));
    SET o_visit_id = LAST_INSERT_ID();

    INSERT INTO visit_symptoms (visit_id, input_method, symptom_text)
    VALUES (o_visit_id, p_input_method, TRIM(p_symptom_text));

    SELECT patient_id, registration_id INTO o_patient_id, o_registration_id
    FROM patients WHERE patient_id = v_patient_id;

    COMMIT;
END$$

CREATE PROCEDURE sp_add_prescription_upload(
    IN p_patient_id BIGINT,
    IN p_visit_id BIGINT,
    IN p_original_filename VARCHAR(255),
    IN p_storage_path VARCHAR(500),
    IN p_mime_type VARCHAR(100),
    IN p_file_size_bytes BIGINT
)
BEGIN
    IF p_file_size_bytes IS NULL OR p_file_size_bytes > 10485760 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'File must be 10 MB or smaller';
    END IF;
    IF p_mime_type NOT IN ('application/pdf','image/jpeg','image/png') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only PDF, JPG, and PNG files are allowed';
    END IF;
    INSERT INTO prescription_uploads
        (patient_id, visit_id, original_filename, storage_path, mime_type, file_size_bytes)
    VALUES
        (p_patient_id, p_visit_id, p_original_filename, p_storage_path, p_mime_type, p_file_size_bytes);
END$$

CREATE PROCEDURE sp_complete_consultation(
    IN p_visit_id BIGINT,
    IN p_doctor_id BIGINT,
    IN p_illness_summary TEXT,
    IN p_diagnosis VARCHAR(500),
    IN p_treatment_plan TEXT,
    IN p_follow_up_on DATE
)
BEGIN
    IF p_illness_summary IS NULL OR CHAR_LENGTH(TRIM(p_illness_summary)) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Illness summary cannot be empty';
    END IF;
    START TRANSACTION;
    UPDATE visits
    SET doctor_id = p_doctor_id, status = 'COMPLETED',
        checked_in_at = COALESCE(checked_in_at, NOW()), completed_at = NOW()
    WHERE visit_id = p_visit_id;
    IF ROW_COUNT() = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Visit was not found';
    END IF;
    INSERT INTO consultation_summaries
        (visit_id, illness_summary, diagnosis, treatment_plan, follow_up_on, reviewed_by_doctor)
    VALUES
        (p_visit_id, TRIM(p_illness_summary), NULLIF(TRIM(p_diagnosis), ''),
         NULLIF(TRIM(p_treatment_plan), ''), p_follow_up_on, TRUE)
    ON DUPLICATE KEY UPDATE
        illness_summary = VALUES(illness_summary), diagnosis = VALUES(diagnosis),
        treatment_plan = VALUES(treatment_plan), follow_up_on = VALUES(follow_up_on),
        reviewed_by_doctor = TRUE;
    COMMIT;
END$$

DELIMITER ;

