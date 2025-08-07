// lib/chat_screen.dart
import 'dart:io'; // For File and Directory
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart' as dash_chat;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/model_response.dart';

import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart'; // <<< Added for file picking
import 'package:permission_handler/permission_handler.dart';
// path_provider is not strictly needed for this specific "pick then load" flow
// but can be useful if you later decide to copy the picked file to app's own directory.
import 'package:uuid/uuid.dart';

class MyChatScreen extends StatefulWidget {
  const MyChatScreen({super.key});

  @override
  State<MyChatScreen> createState() => _MyChatScreenState();
}

class _MyChatScreenState extends State<MyChatScreen> {
  final Uuid _uuid = Uuid(); // For generating unique message IDs
  final FlutterGemmaPlugin _gemma = FlutterGemmaPlugin.instance;
  InferenceModel? _inferenceModel;
  InferenceChat? _chatSession;

  final dash_chat.ChatUser _currentUser = dash_chat.ChatUser(id: '1', firstName: 'You');
  final dash_chat.ChatUser _gemmaUser = dash_chat.ChatUser(id: '2', firstName: 'Gemma', profileImage: 'https://seeklogo.com/images/G/google-gemma-logo-A9139634A5-seeklogo.com.png');

  List<dash_chat.ChatMessage> _messages = <dash_chat.ChatMessage>[];
  bool _isLoadingModel = false; // Initially not loading, will load upon picking
  String _loadingStatusMessage = "Please select a Gemma model file (.task)";
  bool _isGemmaTyping = false;

  final ImagePicker _picker = ImagePicker();

  // To store the name of the picked model for display
  String? _pickedModelName;


  @override
  void initState() {
    super.initState();
    // Don't load automatically, wait for user to pick
    // You could add logic here to load a previously picked model path if you save it to preferences
  }

  Future<bool> _requestFilePickerPermissions() async {
    // For file_picker, on Android, it often uses the Storage Access Framework (SAF)
    // which handles permissions implicitly for the picked file/directory.
    // However, depending on the Android version and specific operations,
    // READ_EXTERNAL_STORAGE might still be beneficial or required by underlying mechanisms.
    // For Android 13+, if file_picker targets specific media types, granular permissions
    // like READ_MEDIA_IMAGES would be used, but for general files, system picker handles it.
    // It's good practice to ensure storage permission if you might read other files or
    // if the plugin relies on it.

    if (Platform.isAndroid) {
      PermissionStatus status = await Permission.storage.request();
      if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return false;
    }
    return true; // For other platforms, assume handled or not needed for basic picker
  }


  Future<void> _pickAndLoadModel() async {
    bool permissionGranted = await _requestFilePickerPermissions();
    if (!permissionGranted) {
      setState(() {
        _loadingStatusMessage = "Storage permission denied. Cannot pick model file.";
        _isLoadingModel = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Storage permission is required to select a model file.")),
      );
      return;
    }

    setState(() {
      _isLoadingModel = true;
      _loadingStatusMessage = "Waiting for model file selection...";
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        // type: FileType.custom,
        // allowedExtensions: ['task'], // Only allow .task files
      );

      if (result != null && result.files.single.path != null) {
        final String pickedFilePath = result.files.single.path!;
        _pickedModelName = result.files.single.name; // e.g., "gemma.task"

        print('Model file picked: $pickedFilePath (Name: $_pickedModelName)');
        setState(() {
          _loadingStatusMessage = "Model '$_pickedModelName' selected. Initializing Gemma...";
        });

        //********************************************************************
        // CORRECTED LINE: Use setModelPath directly with the absolute path
        //********************************************************************
        await _gemma.modelManager.setModelPath(pickedFilePath);
        print('Model path set and installation initiated for: $pickedFilePath');
        // No separate "install" step needed here. setModelPath handles it.

        // After setModelPath, the model should be considered "installed" or "registered"
        // by the plugin using its given path. The subsequent createModel call
        // will then use this registered model.

        setState(() { _loadingStatusMessage = "Creating Gemma model instance..."; });

        _inferenceModel = await _gemma.createModel(
          modelType: ModelType.gemmaIt, // Or your specific model type
          // The model to use will be determined by the previous call to setModelPath
          maxTokens: 2048,
          supportImage: true,
        );

        if (_inferenceModel == null) throw Exception('Failed to create InferenceModel.');
        print('InferenceModel created.');
        setState(() { _loadingStatusMessage = "Creating chat session..."; });
        // ... rest of the method
        _chatSession = await _inferenceModel!.createChat(
          supportImage: true,
        );

        if (_chatSession == null) throw Exception('Failed to create InferenceChat.');
        print('InferenceChat created.');

        setState(() {
          _isLoadingModel = false;
          _loadingStatusMessage = "Gemma is ready!";
          _messages.clear();
          _messages.insert(0, dash_chat.ChatMessage(user: _gemmaUser, createdAt: DateTime.now(), text: "Hi! I'm Gemma (loaded from '$_pickedModelName')."));
        });

      } else {
        // User canceled the picker or something went wrong
        print('Model picking cancelled or failed.');
        setState(() {
          _loadingStatusMessage = "Model selection cancelled. Please select a model.";
          _isLoadingModel = false;
        });
      }
    } catch (e, s) {
      print('CRITICAL ERROR picking or initializing Gemma: $e\n$s');
      setState(() {
        _isLoadingModel = false;
        _pickedModelName = null; // Reset picked model name on error
        _loadingStatusMessage = "Error: ${e.toString().substring(0, (e.toString().length > 100) ? 100 : e.toString().length)}...";
        _messages.insert(0, dash_chat.ChatMessage(user: _gemmaUser, createdAt: DateTime.now(), text: "Gemma Init Error."));
      });
    }
  }

  // --- _loadModelFromDownloads and _getDownloadDirectoryPath are REMOVED ---

  /*Future<void> _sendMessage(dash_chat.ChatMessage dashChatMessage) async {
    if (_chatSession == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Gemma model not loaded. Please select a model file first.")),
      );
      // Optionally, trigger picker again:
      // if (!_isLoadingModel) { // Prevent multiple pick attempts if already loading
      //   _pickAndLoadModel();
      // }
      print("Chat session not initialized! Model needs to be selected and loaded.");
      return;
    }
    // ... (rest of _sendMessage method remains the same as in your provided code)
    setState(() {
      _messages.insert(0, dashChatMessage);
      _isGemmaTyping = true;
    });

    try {
      Message gemmaQueryMessage;

      if (dashChatMessage.medias != null && dashChatMessage.medias!.isNotEmpty) {
        final media = dashChatMessage.medias!.first;
        if (media.type == dash_chat.MediaType.image && media.url.isNotEmpty) {
          final imageBytes = await _loadBytesFromPath(media.url);
          if (imageBytes != null) {
            gemmaQueryMessage = Message.withImage(
              text: dashChatMessage.text.isNotEmpty ? dashChatMessage.text : "Describe this image",
              imageBytes: imageBytes,
              isUser: true,
            );
          } else {
            gemmaQueryMessage = Message.text(
              text: dashChatMessage.text,
              isUser: true,
            );
          }
        } else {
          gemmaQueryMessage = Message.text(
            text: dashChatMessage.text,
            isUser: true,
          );
        }
      } else {
        gemmaQueryMessage = Message.text(
          text: dashChatMessage.text,
          isUser: true,
        );
      }

      await _chatSession!.addQueryChunk(gemmaQueryMessage);

      StringBuffer gemmaResponseBuffer = StringBuffer();
      dash_chat.ChatMessage? gemmaUiMessage;

      await for (final ModelResponse responsePart in _chatSession!.generateChatResponseAsync()) {
        if (!mounted) return;

        if (responsePart is TextResponse) {
          final String token = responsePart.token;
          gemmaResponseBuffer.write(token);

          if (gemmaUiMessage == null) {
            gemmaUiMessage = dash_chat.ChatMessage(
              user: _gemmaUser,
              createdAt: DateTime.now(),
              text: gemmaResponseBuffer.toString(),
            );
            setState(() {
              _messages.insert(0, gemmaUiMessage!);
            });
          } else {
            setState(() {
              final existingMessageIndex = _messages.indexOf(gemmaUiMessage!);
              if (existingMessageIndex != -1) {
                _messages[existingMessageIndex] = dash_chat.ChatMessage(
                  user: gemmaUiMessage!.user,
                  createdAt: gemmaUiMessage!.createdAt,
                  text: gemmaResponseBuffer.toString(),
                  medias: gemmaUiMessage!.medias,
                  quickReplies: gemmaUiMessage!.quickReplies,
                  customProperties: gemmaUiMessage!.customProperties,
                  mentions: gemmaUiMessage!.mentions,
                  status: gemmaUiMessage!.status,
                  replyTo: gemmaUiMessage!.replyTo,
                );
              } else {
                gemmaUiMessage = dash_chat.ChatMessage(
                  user: _gemmaUser,
                  createdAt: DateTime.now(),
                  text: gemmaResponseBuffer.toString(),
                );
                _messages.insert(0, gemmaUiMessage!);
              }
            });
          }
        } else if (responsePart is FunctionCallResponse) {
          print("Function call received: ${responsePart.name}. Not handled in this UI.");
        }
      }
    } catch (e, s) {
      print('Error sending message or processing response: $e');
      print('Stacktrace: $s');
      final errorMessage = dash_chat.ChatMessage(
        user: _gemmaUser,
        createdAt: DateTime.now(),
        text: "Sorry, I encountered an error. ($e)",
      );
      setState(() {
        if (_messages.isNotEmpty && _messages.first.user == _gemmaUser && _messages.first.text.isEmpty && _isGemmaTyping) {
          final gemmaTypingPlaceholderIndex = _messages.indexWhere((m) => m.user == _gemmaUser && m.text.isEmpty);
          if (gemmaTypingPlaceholderIndex != -1) {
            _messages[gemmaTypingPlaceholderIndex] = errorMessage;
          } else {
            _messages.insert(0, errorMessage);
          }
        } else {
          _messages.insert(0, errorMessage);
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGemmaTyping = false;
        });
      }
    }
  }
  */

  Future<void> _sendMessage(dash_chat.ChatMessage dashChatMessage) async {
    if (_chatSession == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Gemma model not loaded. Please select a model file first.")),
      );
      print("Chat session not initialized! Model needs to be selected and loaded.");
      return;
    }

    setState(() {
      _messages.insert(0, dashChatMessage);
      _isGemmaTyping = true;
    });

    try {
      Message gemmaQueryMessage;
      // ... (your existing logic for creating gemmaQueryMessage) ...
      if (dashChatMessage.medias != null && dashChatMessage.medias!.isNotEmpty) {
        final media = dashChatMessage.medias!.first;
        if (media.type == dash_chat.MediaType.image && media.url.isNotEmpty) {
          final imageBytes = await _loadBytesFromPath(media.url);
          if (imageBytes != null) {
            gemmaQueryMessage = Message.withImage(
              text: dashChatMessage.text.isNotEmpty ? dashChatMessage.text : "Describe this image",
              imageBytes: imageBytes,
              isUser: true,
            );
          } else {
            gemmaQueryMessage = Message.text(
              text: dashChatMessage.text,
              isUser: true,
            );
          }
        } else {
          gemmaQueryMessage = Message.text(
            text: dashChatMessage.text,
            isUser: true,
          );
        }
      } else {
        gemmaQueryMessage = Message.text(
          text: dashChatMessage.text,
          isUser: true,
        );
      }

      await _chatSession!.addQueryChunk(gemmaQueryMessage);

      final String gemmaResponseUniqueId = _uuid.v4(); // Generate unique ID

      dash_chat.ChatMessage gemmaResponseUiMessage = dash_chat.ChatMessage(
        user: _gemmaUser,
        createdAt: DateTime.now(),
        text: "", // Start with empty text for streaming
        customProperties: { // Store the unique ID here
          'response_id': gemmaResponseUniqueId,
        },
      );

      setState(() {
        _messages.insert(0, gemmaResponseUiMessage);
      });

      StringBuffer gemmaResponseBuffer = StringBuffer();

      await for (final ModelResponse responsePart in _chatSession!.generateChatResponseAsync()) {
        if (!mounted) return;

        if (responsePart is TextResponse) {
          final String token = responsePart.token;
          gemmaResponseBuffer.write(token);

          setState(() {
            // Find the placeholder message by its customProperty ID
            final int existingMessageIndex = _messages.indexWhere(
                    (m) => m.customProperties != null && m.customProperties!['response_id'] == gemmaResponseUniqueId
            );

            if (existingMessageIndex != -1) {
              // Update the existing message
              _messages[existingMessageIndex] = dash_chat.ChatMessage(
                user: _gemmaUser,
                createdAt: _messages[existingMessageIndex].createdAt, // Keep original timestamp
                text: gemmaResponseBuffer.toString(),
                customProperties: { // Keep the ID
                  'response_id': gemmaResponseUniqueId,
                },
                // Copy other relevant properties from _messages[existingMessageIndex] if needed
                // e.g., medias, quickReplies, mentions, status, replyTo
                medias: _messages[existingMessageIndex].medias,
                quickReplies: _messages[existingMessageIndex].quickReplies,
                // etc.
              );
            } else {
              print("Error: Gemma response message with ID $gemmaResponseUniqueId not found for update.");
              // As a fallback, you might consider adding it if not found, but this indicates a logic issue.
              // For now, just logging.
            }
          });
        } else if (responsePart is FunctionCallResponse) {
          print("Function call received: ${responsePart.name}. Not handled in this UI.");
        }
      }
    } catch (e, s) {
      print('Error sending message or processing response: $e');
      print('Stacktrace: $s');
      setState(() {
        // Attempt to remove a generic "typing" message from Gemma if one exists
        final int streamingMessageIndex = _messages.indexWhere(
                (m) => m.user == _gemmaUser && m.text.isEmpty && (m.customProperties != null && m.customProperties!.containsKey('response_id')));
        if (streamingMessageIndex != -1) {
          _messages.removeAt(streamingMessageIndex);
        }
        _messages.insert(0, dash_chat.ChatMessage(
          user: _gemmaUser,
          createdAt: DateTime.now(),
          text: "Sorry, I encountered an error processing your request. ($e)",
        ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGemmaTyping = false;
        });
      }
    }
  }
  Future<Uint8List?> _loadBytesFromPath(String path) async {
    // ... (this method remains the same as in your provided code)
    try {
      if (path.startsWith('http')) {
        print("Network image loading not implemented in _loadBytesFromPath.");
        return null;
      }
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      } else {
        print("File not found for _loadBytesFromPath: $path");
        return null;
      }
    } catch (e) {
      print("Error loading image bytes from path $path: $e");
      return null;
    }
  }

  void _pickImage(ImageSource source) async {
    if (_inferenceModel == null) { // Or _chatSession == null
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select and load a Gemma model first.")),
      );
      return;
    }
    // ... (rest of _pickImage method remains the same as in your provided code)
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
      );
      if (pickedFile != null) {
        final imageMessage = dash_chat.ChatMessage(
          user: _currentUser,
          createdAt: DateTime.now(),
          text: "Describe this image",
          medias: [
            dash_chat.ChatMedia(
              url: pickedFile.path,
              type: dash_chat.MediaType.image,
              fileName: pickedFile.name,
            )
          ],
        );
        _sendMessage(imageMessage);
      }
    } catch (e) {
      print("Error picking image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image selection error: $e')),
        );
      }
    }
  }

  /*void _startNewConversation() {
    if (_inferenceModel == null) { // Or _chatSession == null
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select and load a Gemma model first.")),
      );
      return;
    }
    // ... (rest of _startNewConversation method remains the same as in your provided code)
    setState(() {
      _isGemmaTyping = false;
    });
    _inferenceModel!.createChat(
      supportImage: true,
    ).then((newSession) {
      setState(() {
        _chatSession = newSession;
        _messages = <dash_chat.ChatMessage>[
          dash_chat.ChatMessage(
            user: _gemmaUser,
            createdAt: DateTime.now(),
            text: "New conversation started. How can I assist you?",
          ),
        ];
      });
    }).catchError((e, s) {
      print("Error creating new chat session: $e\n$s");
      // ... error handling ...
    });
  }
*/
  void _startNewConversation() {
    if (_inferenceModel == null) {
      if (mounted) { // Always check mounted before using context
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select and load a Gemma model first.")),
        );
      }
      return;
    }

    // --- UI Reset ---
    setState(() {
      _messages.clear(); // Clear all existing messages from the UI
      _messages.add(
        dash_chat.ChatMessage( // Add the initial "new conversation" message
          user: _gemmaUser,
          createdAt: DateTime.now(),
          text: "New conversation started. How can I assist you?",
        ),
      );
      _isGemmaTyping = false; // Ensure typing indicator is off
    });
    // --- End of UI Reset ---

    // Since InferenceChat does not have a .close() method,
    // we rely on replacing _chatSession with a new instance
    // to start a fresh conversation. The old session object,
    // if no longer referenced, will be garbage collected by Dart.
    // Any ongoing streams from the old session might continue until they
    // complete or if the underlying native code handles the "orphaning"
    // of the session when a new one is created for the same model.

    // Proceed to create a new backend session for the model
    _inferenceModel!.createChat(
      supportImage: true,
    ).then((newSession) {
      // Only update the _chatSession if the widget is still around
      if (mounted) {
        setState(() {
          _chatSession = newSession;
          // The UI for messages has already been reset above.
          // We just need to ensure _isGemmaTyping is correctly set if createChat took time.
          _isGemmaTyping = false;
        });
      } else {
        // If widget is disposed while createChat was running,
        // the newSession object will eventually be garbage collected
        // as it's not assigned to _chatSession.
        // There's no explicit close needed here if the class doesn't provide it.
        print("New chat session created for a disposed widget. It will be orphaned.");
      }
    }).catchError((e, s) {
      print("Error creating new chat session: $e\n$s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error starting new chat: $e")),
        );
        // Ensure UI reflects the error state
        setState(() {
          _isGemmaTyping = false;
          if (_messages.isNotEmpty && _messages.first.user == _gemmaUser) {
            _messages.first = dash_chat.ChatMessage(
              user: _gemmaUser,
              createdAt: _messages.first.createdAt,
              text: "Error starting new session. Please try again.",
            );
          }
        });
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pickedModelName != null ? 'Gemma: $_pickedModelName' : 'Inference'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _pickAndLoadModel, // Allow picking a new model
            tooltip: 'Select/Change Model File',
          ),
          if (_inferenceModel != null) // Only show if model is loaded
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _startNewConversation,
              tooltip: 'New Conversation',
            ),
        ],
      ),
      body: Column( // Use Column to manage button and chat visibility
        children: [
          if (_inferenceModel == null) // Show selection UI if no model loaded
            Expanded( // Make it take available space
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoadingModel)
                        const CircularProgressIndicator()
                      else
                        const Icon(Icons.model_training_outlined, size: 80, color: Colors.grey),
                      const SizedBox(height: 20),
                      Text(
                        _loadingStatusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      if (!_isLoadingModel) // Show button only if not currently loading
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text("Select Gemma Model File (.task)"),
                          onPressed: _pickAndLoadModel,
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
          else // Show Chat UI if model is loaded
            Expanded(
              child: dash_chat.DashChat(
                currentUser: _currentUser,
                onSend: _sendMessage,
                messages: _messages,
                typingUsers: _isGemmaTyping ? [_gemmaUser] : [],
                inputOptions: dash_chat.InputOptions(
                  leading: [
                    IconButton(
                      icon: const Icon(Icons.image_outlined),
                      onPressed: () {
                        // Show bottom sheet to choose camera or gallery
                        showModalBottomSheet(
                          context: context,
                          builder: (BuildContext bc) {
                            return SafeArea(
                              child: Wrap(
                                children: <Widget>[
                                  ListTile(
                                      leading: const Icon(Icons.photo_library),
                                      title: const Text('Gallery'),
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _pickImage(ImageSource.gallery);
                                      }),
                                  ListTile(
                                    leading: const Icon(Icons.photo_camera),
                                    title: const Text('Camera'),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      _pickImage(ImageSource.camera);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      tooltip: 'Attach Image',
                    ),
                  ],
                ),
                messageOptions: dash_chat.MessageOptions(
                  showCurrentUserAvatar: true,
                  showOtherUsersAvatar: true,
                  maxWidth: MediaQuery.of(context).size.width * 0.60,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _inferenceModel?.close(); // Close the inference model when the widget is disposed
    super.dispose();
  }
}
