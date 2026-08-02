-- Supabase Schema for Medical Appointment System

-- 1. Profiles Table (Unified User Table)
CREATE TABLE profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    full_name TEXT NOT NULL,
    role TEXT CHECK (role IN ('doctor', 'patient')) NOT NULL,
    phone TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Doctors Table (Extended Info)
CREATE TABLE doctors (
    id UUID REFERENCES profiles(id) ON DELETE CASCADE PRIMARY KEY,
    specialization TEXT,
    avg_session_duration INTEGER DEFAULT 30, -- in minutes
    buffer_time INTEGER DEFAULT 5, -- in minutes
    start_time TIME DEFAULT '09:00:00',
    end_time TIME DEFAULT '17:00:00',
    is_available BOOLEAN DEFAULT TRUE
);

-- 3. Appointments Table
CREATE TABLE appointments (
    id BIGSERIAL PRIMARY KEY,
    doctor_id UUID REFERENCES doctors(id) ON DELETE CASCADE,
    patient_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    patient_name TEXT NOT NULL,
    patient_phone TEXT NOT NULL,
    patient_age INTEGER NOT NULL,
    patient_gender TEXT CHECK (patient_gender IN ('Male', 'Female')) NOT NULL,
    symptoms TEXT,
    appointment_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    status TEXT CHECK (status IN ('Scheduled', 'Completed', 'Canceled', 'Expired')) DEFAULT 'Scheduled',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;

-- Policies (Simplified for demo)
CREATE POLICY "Public profiles are viewable by everyone" ON profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Doctors are viewable by everyone" ON doctors FOR SELECT USING (true);
CREATE POLICY "Doctors can update own settings" ON doctors FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Patients can view own appointments" ON appointments FOR SELECT USING (auth.uid() = patient_id);
CREATE POLICY "Doctors can view appointments assigned to them" ON appointments FOR SELECT USING (auth.uid() = doctor_id);
CREATE POLICY "Patients can insert appointments" ON appointments FOR INSERT WITH CHECK (auth.uid() = patient_id);
CREATE POLICY "Users can update own appointments" ON appointments FOR UPDATE USING (auth.uid() = patient_id OR auth.uid() = doctor_id);
