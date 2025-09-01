/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {onRequest} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

/**
 * Simple Cloud Function exported to satisfy predeploy lint and provide a
 * minimal health endpoint for the project. This uses the v2 onRequest
 * HTTP trigger and the firebase logger.
 */

exports.helloWorld = onRequest((req, res) => {
	logger.info('helloWorld called', { path: req.path });
	res.status(200).send('Hello from Firebase Functions');
});
