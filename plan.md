# main dependency
* https://github.com/PureSwift/Bluetooth

# Peripherals

dont know if we should make 
```swift
@Peripherals(...filter options) var peripherals 
```
which updates the view when new peripherals..

in terms of getting the peripheral value updates of whatever it 
passes im not sure what makes most sense yet..

make peripheral or whatever class name ends up as 
as observable class 
soo we can just pass the elements of peripherals to
some view and it will internal detect changes..
we can figure that out later on what extactly it should do 
to detect changes.. 

for now just sooo some List / ScrollView can detect peripherals
and display them we can press them and get some info..

but we are not making ANY UI

only thing we do for nucleantui is the EnvironmentValues and \.someBlueThing

# Manager

get the instance of the manager by
```swift
@Environment(\.bluetoothManager) var ble
```


# start by testing with iOS since only thing we got with ble atm..

