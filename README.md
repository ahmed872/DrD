# Medical Appointment System for Local Villages

A Flutter application built with **Clean Architecture** and **Supabase** backend. Designed specifically for rural areas with **Arabic (RTL)** support and a clean medical theme.

## 🚀 Features

- **Doctor Mode**: Manage schedule, session duration, buffer time, and daily patient list.
- **Patient Mode**: Browse doctors, real-time slot booking.
- **Auto Slot Generation**: Logic to calculate slots based on doctor settings.
- **Arabic Support**: Full RTL layout and Arabic localization.
- **Live Countdown**: Real-time timer for the next appointment.
- **Strict Policy**: 10-minute late expiration for slots.

## 🏗️ Architecture (Clean Architecture)

- **Domain Layer**: Entities, Use Cases, Repository Interfaces.
- **Data Layer**: Models (DTOs), Repository Implementations, Supabase Data Sources.
- **Presentation Layer**: Providers (State Management), Screens, Widgets.
- **Core**: Utilities like `TimeSlotGenerator`.

## 🛠️ Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL)
- **State Management**: Provider
- **Localization**: flutter_localizations

## 📋 Database Setup (Supabase)

The database schema is located in `supabase/schema.sql`. Run these SQL commands in your Supabase SQL Editor:

1. `profiles`: Stores user info (Doctor/Patient).
2. `doctors`: Stores doctor-specific settings (Schedule, Duration).
3. `appointments`: Stores booking details and status.

## ⏱️ Slot Logic

The logic is implemented in `lib/core/utils/time_slot_generator.dart`.
- **Duration**: Custom per doctor.
- **Buffer**: Added between slots.
- **Expiration**: Slots mark as 'Expired' if current time > slot start + 10 mins.

## 📁 Folder Structure

```text
lib/
├── core/             # Utils, constants, themes
├── data/             # Models, repo implementations
├── domain/           # Entities, use cases, repo interfaces
├── presentation/     # Screens, providers, widgets
└── main.dart         # Entry point
```
