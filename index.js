// main index.js

import { NativeModules, NativeEventEmitter, AppState } from 'react-native';
const _RNCouchbaseLite =  NativeModules.RNCouchbaseLite;
const RNCouchbaseLite = {};


// RNCouchbaseLite - Functions
const functions = Object.getOwnPropertyNames(_RNCouchbaseLite).filter(item => typeof _RNCouchbaseLite[item] === 'function');
functions.forEach((functionName) => {
	RNCouchbaseLite[functionName] = async (...params) => {
		if (params.length < 1 || params[0] === undefined) {
			// If No Parameters, Call With Empty Object
			return _RNCouchbaseLite[functionName]({});
		}
		// Call With Parameters
		return _RNCouchbaseLite[functionName](...params);
	};
});


// RNCouchbaseLite - Events
RNCouchbaseLite.Events = {};
RNCouchbaseLite.Events.listenerTokens = [];
RNCouchbaseLite.Events.eventEmitter = new NativeEventEmitter(_RNCouchbaseLite);
RNCouchbaseLite.Events.addListener = RNCouchbaseLite.Events.eventEmitter.addListener;
RNCouchbaseLite.Events.setEventHandler = async (eventFunction) => {
	const events = await RNCouchbaseLite.getEvents();
	events.forEach((eventName) => {
		RNCouchbaseLite.Events.setListener(eventName, eventFunction);
	});
};
RNCouchbaseLite.Events.setListener = async (eventName, eventFunction) => {
	RNCouchbaseLite.Events.eventEmitter.removeAllListeners(eventName);
	RNCouchbaseLite.Events.listenerTokens[eventName] = RNCouchbaseLite.Events.eventEmitter.addListener(eventName, (eventData) => {
		eventFunction(eventName, eventData);
	});
};
RNCouchbaseLite.Events.removeAllListeners = async (eventName) => {
	if (typeof(eventName) === 'string') {
		RNCouchbaseLite.Events.eventEmitter.removeAllListeners(eventName);
		return;
	}
	const events = await RNCouchbaseLite.getEvents();
	events.forEach(RNCouchbaseLite.Events.eventEmitter.removeAllListeners);
};
 

// App State Event Listener
// Databases and Replicators need to be suspended whe the app goes into the background state, and resume when the app is made active.
// When going into background, the event is fired twice. Once with 'nextAppState' as 'inactive', then as 'background'
// When going active, the event fires once: 'active'
// When resuming active state, non-suspended Replicators (if not yet nil) will fire the 'Replication.Change' event with 'offline', then 'busy', etc.
RNCouchbaseLite.Events.appStateListener = AppState.addEventListener('change', (nextAppState) => {
	if (nextAppState === 'background') { // Prepare for background state
		RNCouchbaseLite.suspendConnections();
	}
	if (nextAppState === 'active') { // Prepare for app to resume
		RNCouchbaseLite.resumeConnections();
	}
});


// Export
export default RNCouchbaseLite;
