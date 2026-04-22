# Custom MessageQueue Implementation

This project provides a custom in-memory MessageQueue implementation that replaces the need for System.Messaging and MSMQ installation.

## Overview

The custom implementation provides:
- **In-memory message queues** that don't require MSMQ
- **Thread-safe operations** using concurrent collections
- **Compatible API** with System.Messaging.MessageQueue
- **Async support** for modern applications
- **No external dependencies**

## Key Components

### 1. IMessageQueue Interface
```csharp
public interface IMessageQueue
{
    string QueueName { get; }
    int Count { get; }
    void Send(object message, string label = null, MessagePriority priority = MessagePriority.Normal);
    QueueMessage Receive(TimeSpan timeout = default);
    QueueMessage Peek(TimeSpan timeout = default);
    Task<QueueMessage> ReceiveAsync(TimeSpan timeout = default, CancellationToken cancellationToken = default);
    List<QueueMessage> GetAllMessages();
    void Purge();
}
```

### 2. InMemoryMessageQueue
Thread-safe implementation using `ConcurrentQueue<T>` for message storage.

### 3. MessageQueueManager
Static manager for creating and accessing queues:
```csharp
// Create or get a queue
var queue = MessageQueueManager.Create("MyQueue");

// Check if queue exists
bool exists = MessageQueueManager.Exists("MyQueue");

// Get existing queue
var queue = MessageQueueManager.GetQueue("MyQueue");
```

### 4. MessageQueue (Compatibility Layer)
Drop-in replacement for System.Messaging.MessageQueue:
```csharp
// Create queue
var queue = MessageQueue.Create(@".\Private$\MyQueue");

// Send message
queue.Send("Hello World!", "My Label");

// Receive message
var message = queue.Receive();
```

## Usage Examples

### Basic Queue Operations
```csharp
// Create a queue
var queue = MessageQueue.Create("TestQueue");

// Send messages
queue.Send("Hello World!", "Simple Message");
queue.Send(new { Name = "John", Age = 30 }, "JSON Object");

// Receive messages
var message1 = queue.Receive();
var message2 = queue.Receive();

// Clean up
MessageQueue.Delete("TestQueue");
```

### Notification Service
The `NotificationService` has been updated to use the custom implementation:
```csharp
var notificationService = new NotificationService();

// Send notification
notificationService.SendNotification("Student", "123", "John Doe", 
    EntityOperation.CREATE, "admin");

// Receive notification
var notification = notificationService.ReceiveNotification();
```

### Async Operations
```csharp
var queue = MessageQueueManager.Create("AsyncQueue");

// Send message
queue.Send("Async Message", "Label");

// Receive asynchronously
var message = await queue.ReceiveAsync(TimeSpan.FromSeconds(5));
```

## Testing

A test controller is provided at `/MessageQueueTest` with the following features:
- Send test notifications
- Receive notifications
- Test basic queue operations
- View queue status

## Migration from System.Messaging

To migrate from System.Messaging:

1. Remove `System.Messaging` references
2. Add the custom Infrastructure classes
3. Update using statements:
   ```csharp
   // Old
   using System.Messaging;
   
   // New
   using ContosoUniversity.Infrastructure;
   ```
4. The API remains largely the same

## Limitations

- **In-memory only**: Messages are lost when application restarts
- **Single machine**: Cannot distribute across multiple servers
- **No persistence**: No built-in database or file storage
- **Basic features**: Advanced MSMQ features are not implemented

## Production Considerations

For production use, consider:
- Implementing persistence (database, files, etc.)
- Using a proper message broker (RabbitMQ, Azure Service Bus, etc.)
- Adding authentication and authorization
- Implementing message durability and delivery guarantees

## Files Created

- `Infrastructure\IMessageQueue.cs` - Core interface
- `Infrastructure\InMemoryMessageQueue.cs` - In-memory implementation
- `Infrastructure\MessageQueueManager.cs` - Queue management
- `Infrastructure\MessageQueue.cs` - Compatibility layer
- `Infrastructure\Message.cs` - Message and formatter classes
- `Infrastructure\MessageQueueExceptions.cs` - Exception types
- `Controllers\MessageQueueTestController.cs` - Test controller
- `Views\MessageQueueTest\Index.cshtml` - Test UI
- `Examples\MessageQueueExample.cs` - Usage examples

## Benefits

? **No MSMQ dependency**  
? **Thread-safe operations**  
? **Compatible API**  
? **Easy to test**  
? **No external installation required**  
? **Async support**  
? **Lightweight**