/**
 * @format
 */

import { registerRootComponent } from 'expo';

import App from './App';

// registerRootComponent registers under the module name "main", which is what
// AppDelegate.swift starts React Native with. Entering through it rather than
// through AppRegistry directly is what pulls the Expo runtime into the bundle.
registerRootComponent(App);
