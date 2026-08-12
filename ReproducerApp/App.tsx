import { Text, View } from 'react-native';
import { SymbolView } from 'expo-symbols';

// A single mounted SymbolView is the whole reproduction: under the
// react-native 0.86.2 prebuilt core, mounting it in a Release build corrupts
// the heap during the first mounting transaction on most cold launches.
function App() {
  return (
    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
      <Text>rn-0862 reproducer</Text>
      <SymbolView name="gearshape" tintColor="#000000" size={22} />
    </View>
  );
}

export default App;
