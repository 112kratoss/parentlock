/// Supabase Configuration
/// 
/// Replace these values with your actual Supabase project credentials.
/// You can find these in your Supabase dashboard:
/// Project Settings → API → Project URL and anon/public key
library;

class SupabaseConfig {
  // TODO: Replace with your Supabase project URL
  static const String supabaseUrl = 'https://clycrthzxpjwxrqlqkqv.supabase.co';
  
  // TODO: Replace with your Supabase anon/public key
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNseWNydGh6eHBqd3hycWxxa3F2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY5MjIzMzQsImV4cCI6MjA4MjQ5ODMzNH0.6xaXqTUjTTE2gAJYN5Wkhs26L6wUEe8PofiOTCC7eWY';
  
  // Private constructor to prevent instantiation
  SupabaseConfig._();
}
