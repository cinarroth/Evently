import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Maps backend error codes onto friendly, actionable copy. The stable
/// machine token (first word of the callable message) decides the mapping, so
/// changing prose in functions never breaks the apps.
String friendlyError(Object error) {
  if (error is FirebaseFunctionsException) {
    final token = (error.message ?? '').split(' ').first;
    switch (token) {
      case 'ALREADY_REGISTERED':
        return 'You are already registered for this event.';
      case 'NOT_REGISTERED':
        return 'You have no registration for this event.';
      case 'EVENT_FULL':
        return 'This event is full — all spots are taken.';
      case 'EVENT_CANCELED':
        return 'This event was canceled.';
      case 'EVENT_STARTED':
        return 'Registration is closed; the event already started.';
      case 'EVENT_COMPLETED':
        return 'This event has ended.';
      case 'INVALID_QR':
        return 'This QR code is not valid for this event.';
      case 'ALREADY_CHECKED_IN':
        return 'This participant is already checked in.';
      case 'CAPACITY_BELOW_COUNT':
        return 'Capacity cannot go below the current participant count.';
      case 'EVENT_NOT_UPCOMING':
        return 'Reminders can only be sent for upcoming events.';
    }
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to do that.';
      case 'unauthenticated':
        return 'Please sign in first.';
      case 'not-found':
        return 'Not found.';
      case 'already-exists':
        return 'Already exists.';
      case 'resource-exhausted':
        return 'No spots remaining.';
      case 'failed-precondition':
        return 'That action is not possible right now.';
      case 'invalid-argument':
        return error.message ?? 'Invalid input.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Please choose a stronger password (min. 6 characters).';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  debugPrint('Untranslated error: $error');
  return 'Something went wrong. Please try again.';
}
