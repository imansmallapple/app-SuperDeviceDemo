# Super Device Demo - Troubleshooting Guide

## Summary of Cross-Device Data Synchronization Issues

This document summarizes the common errors encountered during the development of cross-device data synchronization functionality and their solutions.

---

## 🔍 Root Causes of Synchronization Failures

### 1. **Missing Required Permission** ❌

**Issue:** Missing essential permission in `module.json5`

```json
{
  "requestPermissions": [
    {
      "name": "ohos.permission.DISTRIBUTED_DATASYNC"
    },
    // ❌ Missing this critical permission
    {
      "name": "ohos.permission.ACCESS_SERVICE_DM"
    }
  ]
}
```

**Impact:** DeviceManager cannot function properly, unable to discover and bind devices

**Solution:** Add `ohos.permission.ACCESS_SERVICE_DM` permission to `module.json5`

---

### 2. **Incorrect `bindTarget` Parameters** ❌

**Issue:** Error code `401` - Invalid parameters

**Wrong Implementation:**
```typescript
let bindParam = {
  'bindType': '1',  // ❌ Should be number, not string
  'appName': context.applicationInfo.name,  // ❌ Incorrect path
}
```

**Correct Implementation:**
```typescript
let bindParam: Record<string, string | number> = {
  'bindType': 1,  // ✅ Number type
  'targetPkgName': context.abilityInfo.bundleName,
  'appName': context.abilityInfo.labelId.toString(),
  'appOperation': 'SuperDevice data sync',
  'customDescription': 'Allow data synchronization'
}
```

**Key Points:**
- `bindType` must be a number (1 for PIN authentication)
- Use correct context paths for application information
- Include descriptive fields for better user experience

---

### 3. **Incorrect `bindTarget` Callback Handling** ❌

**Issue:** `err.code=0` (success) incorrectly treated as an error

**Wrong Implementation:**
```typescript
this.myDeviceManager.bindTarget(deviceId, bindParam, (err: BusinessError) => {
  if (err) {  // ❌ err.code=0 still enters this branch
    Log.error('authenticateDevice error')
    return;
  }
})
```

**Correct Implementation:**
```typescript
this.myDeviceManager.bindTarget(deviceId, bindParam, (err: BusinessError) => {
  if (err && err.code !== 0) {  // ✅ Only non-zero codes are errors
    Log.error('authenticateDevice error')
    return;
  }
  Log.info('bindDevice success')
  // Handle success...
})
```

---

### 4. **Incorrect `startDiscovering` Parameters** ❌

**Issue:** Invalid filter parameter structure

**Wrong Implementation:**
```typescript
this.myDeviceManager.startDiscovering(
  { discoverTargetType: 1 },
  { availableStatus: 0 }  // ❌ Incorrect parameter
);
```

**Correct Implementation:**
```typescript
this.myDeviceManager.startDiscovering(
  { discoverTargetType: 1 }
);
```

---

### 5. **ID Type Confusion: `deviceId` vs `networkId`** ❌❌❌

**This is the MOST CRITICAL error!**

HarmonyOS devices have two types of identifiers:
- **`deviceId`**: Local unique device identifier
- **`networkId`**: Network ID used for cross-device communication

**Wrong Usage:**
```typescript
// ❌ Error 1: Storing deviceId instead of networkId
AppStorage.setOrCreate('RemoteConnectDeviceId', remoteDevice.deviceId)

// ❌ Error 2: Using deviceId in startAbility
let wantValue: Want = {
  deviceId: device.deviceId,  // Wrong!
  // ...
}

// ❌ Error 3: Using deviceId for kvStore.sync
this.kvStore.sync([deviceId], ...)
```

**Correct Usage:**
```typescript
// ✅ Correct 1: Store networkId
AppStorage.setOrCreate('RemoteConnectDeviceId', remoteDevice.networkId)

// ✅ Correct 2: Use networkId in startAbility
let wantValue: Want = {
  deviceId: device.networkId,  // Correct!
  bundleName: context.abilityInfo.bundleName,
  abilityName: 'EntryAbility',
  parameters: { ... }
}

// ✅ Correct 3: Use networkId for kvStore.sync
this.kvStore.sync([networkId], distributedKVStore.SyncMode.PUSH_PULL);
```

**Rule of Thumb:**
- Use `deviceId` only for local device identification
- Use `networkId` for ALL cross-device operations (startAbility, kvStore.sync, etc.)

---

### 6. **Incorrect `kvStore.sync()` Invocation** ❌

**Issue:** Incorrectly treating `sync()` as a Promise or callback-based method

**Wrong Implementations:**
```typescript
// ❌ Error 1: Using .then()
this.kvStore.sync([deviceId], mode).then(...)
// Compilation error: Property 'then' does not exist on type 'void'

// ❌ Error 2: Using callback
this.kvStore.sync([deviceId], mode, (err) => {...})
// Compilation error: No overload matches this call
```

**Correct Implementation:**
```typescript
// ✅ sync() returns void, call it directly
try {
  this.kvStore.sync([networkId], distributedKVStore.SyncMode.PUSH_PULL);
  Log.info('sync triggered')
} catch (error) {
  Log.error('sync exception:', error)
}

// ✅ Listen to syncComplete event for results
this.kvStore.on('syncComplete', (data) => {
  Log.info('syncComplete:', JSON.stringify(data));
});
```

**Method Signature:**
```typescript
sync(deviceIds: string[], mode: SyncMode, delayMs?: number): void
```

---

### 7. **Inconsistent Parameter Names in EntryAbility** ❌

**Issue:** Mismatched parameter names between sender and receiver

**Wrong Implementation:**
```typescript
// Sender (DeviceManager.ts)
parameters: { shared_list: JSON.stringify(data) }

// Receiver (EntryAbility.ets)
if (this.want?.parameters?.messageList) {  // ❌ Wrong name
  // ...
}

// Another receiver method
if (this.want?.parameters?.shared_data) {  // ❌ Different wrong name
  // ...
}
```

**Correct Implementation:**
```typescript
// Sender
parameters: { shared_list: JSON.stringify(data) }

// Receiver - onNewWant
if (this.want?.parameters?.shared_list) {  // ✅ Consistent
  let messageList = JSON.parse(this.want.parameters.shared_list as string)
  this.storage.setOrCreate('messageList', messageList)
}

// Receiver - onWindowStageCreate
if (this.want?.parameters?.shared_list) {  // ✅ Consistent
  let messageList = JSON.parse(this.want.parameters.shared_list as string)
  this.storage.setOrCreate('messageList', messageList)
}
```

---

### 8. **Data Reception Logic Errors** ❌❌

**Issue 1: Iterating Wrong Array**
```typescript
if (data.insertEntries.length > 0) {
  data.updateEntries.forEach(...)  // ❌ Should iterate insertEntries
}
```

**Issue 2: Data Duplication**
```typescript
this.receivedList = this.receivedList.concat(value)  // ❌ Causes duplicates
```

**Issue 3: Sender Displays Received Messages**
```typescript
// No check for sender role, causing sender's own messages to appear in receivedList
```

**Correct Implementation:**
```typescript
createKVStore(): void {
  this.kvStoreModel.createKvStore(this.context, (data: distributedKVStore.ChangeNotification) => {
    Log.info('kvStore', 'dataChange deviceId:', data.deviceId, 'isSender:', this.isSender)
    
    // ✅ Sender should not process received messages
    if (this.isSender) {
      Log.info('kvStore', 'sender ignore dataChange')
      return
    }
    
    // ✅ Iterate correct array
    if (data.insertEntries.length > 0) {
      data.insertEntries.forEach((entry) => {
        Log.info('kvStore', 'inside insert', entry.key, entry.value.type, entry.value.value)
        const value = JSON.parse((entry.value.value) as string) as string[]
        this.receivedList = value  // ✅ Direct replacement, no concat
        Log.info('kvStore', 'receivedList after insert:', this.receivedList)
      })
    }
    
    if (data.updateEntries.length > 0) {
      data.updateEntries.forEach((entry) => {
        Log.info('kvStore', 'inside update', entry.key, entry.value.type, entry.value.value)
        const value = JSON.parse((entry.value.value) as string) as string[]
        this.receivedList = value  // ✅ Direct replacement
        Log.info('kvStore', 'receivedList after update:', this.receivedList)
      })
    }
  })
}
```

---

## 📊 Error Priority Ranking

| Priority | Error | Impact |
|----------|-------|--------|
| 🔴 P0 | ID Type Confusion (`deviceId` vs `networkId`) | All cross-device operations fail |
| 🔴 P0 | Missing Permission (`ACCESS_SERVICE_DM`) | DeviceManager cannot function |
| 🟠 P1 | Incorrect `bindTarget` Parameters | Device pairing fails (401 error) |
| 🟠 P1 | Incorrect `kvStore.sync()` Invocation | Compilation failure |
| 🟡 P2 | Data Reception Logic Errors | Data duplication/display issues |
| 🟡 P2 | Inconsistent Parameter Names | Data transfer failure |

---

## ✅ Complete Checklist for Cross-Device Development

### Configuration
- [ ] Add `ohos.permission.ACCESS_SERVICE_DM` permission
- [ ] Add `ohos.permission.DISTRIBUTED_DATASYNC` permission
- [ ] Configure app as system-level application
- [ ] Ensure proper signature configuration

### DeviceManager
- [ ] Use `networkId` (not `deviceId`) for remote device storage
- [ ] Correct `bindTarget` parameters with numeric `bindType`
- [ ] Proper error handling: `if (err && err.code !== 0)`
- [ ] Use `networkId` in `startAbility` Want object

### KvStore Synchronization
- [ ] Use `networkId` for `kvStore.sync()`
- [ ] Call `sync()` directly without Promise/callback
- [ ] Add `syncComplete` event listener
- [ ] Enable sync with `kvStore.enableSync(true)`

### Data Reception
- [ ] Iterate correct array (`insertEntries` vs `updateEntries`)
- [ ] Parse JSON data correctly
- [ ] Direct replacement instead of concatenation
- [ ] Sender ignores `dataChange` events
- [ ] Consistent parameter names across components

### Testing
- [ ] Two devices on same network
- [ ] Permissions granted on both devices
- [ ] PIN verification works
- [ ] Data syncs from sender to receiver
- [ ] Sender only shows sent messages
- [ ] Receiver only shows received messages
- [ ] No data duplication

---

## 🔗 Related Documentation

- [HarmonyOS DeviceManager Guidelines](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/devicemanager-guidelines)
- [Distributed KVStore Development](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-sync-of-distributed-data-object)

---

## 📝 Key Takeaways

1. **Always use `networkId` for cross-device operations** - This is the most common mistake
2. **Check method signatures carefully** - Don't assume async patterns where they don't exist
3. **Test error handling thoroughly** - Error code 0 means success in callbacks
4. **Separate sender and receiver logic** - Prevent unintended data processing
5. **Keep parameter names consistent** - Across all components and methods

These errors are interconnected - any single one can cause complete failure of cross-device functionality!
