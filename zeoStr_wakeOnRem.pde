/*
 * ZeoLibrary example: zeoStr_lucidSound
 *
 * Connect Zeo Bedside Display via serial port
 * 
 * Plays mp3-file 5 minutes into REM sleep
 * to help trigger lucid dreaming
 */

import processing.serial.*;
import src.zeo.library.*;
import ddf.minim.*;

import java.util.Date;
import java.text.SimpleDateFormat;
// Add this at the beginning of the file
import java.util.LinkedList;
import java.util.Queue;
import java.time.LocalDateTime;
import java.time.ZoneOffset;


// Add this to the global variables
Queue<Integer> sleepStageHistory = new LinkedList<>();
int historyDuration = 20; // 20 slices of 30 seconds each to make 10 minutes


// sound starts after 5 minutes into REM stage
int remDelay = 5;

// duration of sound to play, in seconds
int playDuration = 180;

// name of mp3 soundfile, placed in data folder
String soundFile = "BM207.mp3";  


ZeoStream zeo;    // stream object
int sleepStage = 0;
int counter = 0;
int remCounter = 0;

PFont myFont;

AudioPlayer player;
Minim minim;

// colors and names for WAKE, REM, LIGHT and DEEP sleep stages
color[] stageColor = { color(255,255,255), color(255,0,0), color(50,255,50), color(150,150,150), color(0,150,0) };
String[] stageName = { "", "Wake", "REM", "Light", "Deep" };


double alarmInNHours = 4.3;

LocalDateTime alarmTime;
LocalDateTime lastSleepStageTime;

void setup() {
if (P3D == OPENGL) println("I am run on Processing 2.0");
  alarmTime = LocalDateTime.now().plusHours((long) alarmInNHours);
  println("alarmTime: " + alarmTime);
 
  size(200,150);
  
  myFont = createFont("", 20);
  textFont(myFont);
  
  minim = new Minim(this);
  // load a file, give the AudioPlayer buffers that are 2048 samples long
  player = minim.loadFile(soundFile, 2048);
  // play soundfile on startup, to test and to adjust sound volume
  player.play();
  
  
  // print serial ports
  println(Serial.list());
  // select serial port for ZEO
  String portName = "";
  for (String port : Serial.list()) {
    if (port.contains("usbserial")) {
      System.out.println("found port: "+port);
      portName = port;
      break;
    }
  }
  zeo = new ZeoStream(this, portName);
  zeo.debug = false;
  // start to read data from serial port
  zeo.start();
}


void draw() {
  
  // background color represents sleep stage
  background(stageColor[sleepStage]);
  fill(210);
  text(getTime(), 20, 40);    // print time
  text(stageName[sleepStage], 20, 70);  // print sleep stage

  if(remCounter > 0) {
    remCounter--;
    
    if(remCounter <=0) {
      if(player.isPlaying()) {
        text("sound is playing!", 20, 100);
        // if sound is playing, STOP sound
        REMstop(); 
      } else {
        // if no sound is playing, START sound
        REMevent();
      }
    }
  }

}

int cooldown = 0;

// triggers when a new data package is received
public void zeoSliceEvent(ZeoStream z) {
  // System.out.println("zeoSliceEvent triggered");
  // System.out.println("Timestamp: " + sdf.format(date));
  // System.out.println("Sleep State: " + z.slice.sleepState);
  // System.out.println("Impedance: " + z.slice.impedance);
  // System.out.println("Signal Quality Index (SQI): " + z.slice.SQI);
  // System.out.println("Bad Signal Flag: " + z.slice.badSignal);
}

// Modify the zeoSleepStateEvent method
public void zeoSleepStateEvent(ZeoStream z) {
  if (cooldown > 0) {
    cooldown--;
  }

  // Update sleep stage history
  sleepStageHistory.add(z.sleepState);
  if (sleepStageHistory.size() > historyDuration) {
    sleepStageHistory.poll();
  }

  // println("Sleep stage history: " + sleepStageHistory);

  if (sleepStage != z.sleepState) {
    // change of sleep stage
      Date date = new Date(z.slice.timestamp * 1000L); // Convert seconds to milliseconds
      SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
      long durationInSeconds = java.time.Duration.between(lastSleepStageTime, LocalDateTime.ofEpochSecond(z.slice.timestamp, 0, ZoneOffset.UTC)).getSeconds();
      println("Sleep stage changed from " + stageName[sleepStage] + " to " + stageName[z.sleepState] + ", Timestamp: " + sdf.format(date) + ", current sleep stage: " + z.sleepState + ", duration of last sleep stage: " + durationInSeconds + " seconds, every 10min the cooldown is: " + cooldown + ", isMostlyREM: " + isMostlyREM() + ", isRecentREM: " + isRecentREM());
  }
  if (isRecentDisconnected()) {
    println("Recent disconnected, skipping REM finished event");
  }
    // Check if we just finished a REM cycle
  if (isMostlyREM() && !isRecentREM() && cooldown == 0 && !isRecentDisconnected()) {
    logFinishedREMCycle();
    onRemFinished(z.slice);
    cooldown = 40;  // wait 20 minutes (20 minutes / 0.5 minutes per cooldown value)
  }

  sleepStage = z.sleepState;
  lastSleepStageTime = LocalDateTime.ofEpochSecond(z.slice.timestamp, 0, ZoneOffset.UTC);
}

boolean isRecentDisconnected() {
  int recentCount = sleepStageHistory.size() / 10;
  int emptyCount = 0;
  int index = 0;
  for (int stage : sleepStageHistory) {
    if (index >= sleepStageHistory.size() - recentCount) {
      if (stage == 0) { // Assuming 0 represents an empty event
        emptyCount++;
      }
    }
    index++;
  }
  return emptyCount > recentCount / 2;
}


public void onRemFinished(ZeoSlice slice) {
  if (LocalDateTime.ofEpochSecond(slice.timestamp, 0, ZoneOffset.UTC).isAfter(alarmTime)) {
    SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
    println("alarmTime passed! and just finished REM cycle at " + sdf.format(new Date(slice.timestamp * 1000L)));
    // play sound
    REMevent();
    return;
  }
  final double diff = java.time.temporal.ChronoUnit.MILLIS.between(
      java.time.Instant.ofEpochSecond(slice.timestamp).atZone(java.time.ZoneOffset.UTC).toLocalDateTime(), 
      alarmTime
  );
  final double diffInHours = diff / 3600000;
  if (diffInHours > 1.5) {
    println("Sleep, more cycles can be done, diffInHours: " + diffInHours);
    return;
  }
  if (diff < 0.3) {
    println("You finished rem and your alarm is in 20min, waking up now");
    REMevent();
    return;
  }
  println("You finished REM and your alarm is in more than 20min, sleeping now");
}

// Add this helper method to check if the past 10 minutes were mostly REM
boolean isMostlyREM() {
  int remCount = 0;
  for (int stage : sleepStageHistory) {
    if (stage == 2) {
      remCount++;
    }
  }
  // println("REM count: " + remCount + ", Total count: " + sleepStageHistory.size());
  return remCount > sleepStageHistory.size() / 2;
}

// Add this helper method to check if the last 10% of the queue is not mostly REM
boolean isRecentREM() {
  int recentCount = sleepStageHistory.size() / 10;
  int remCount = 0;
  int index = 0;
  for (int stage : sleepStageHistory) {
    if (index >= sleepStageHistory.size() - recentCount) {
      if (stage == 2) {
        remCount++;
      }
    }
    index++;
  }
  return remCount > recentCount / 2;
}

// start sound 5 minutes into REM sleep
public void REMevent() {
  // turn on music!
  println(getTime()+"\tREM sleep, start playing sound");
  player.loop();
  remCounter = (int) frameRate*playDuration;  // play for 180 seconds
}

// Add this helper method to log the finished REM cycle
void logFinishedREMCycle() {
  String currentTime = getTime();
  println(currentTime + "\tFinished REM cycle");
  Date date = new Date();
  SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
  println("Date and Time: " + sdf.format(date));
}

// stop sound
public void REMstop() {
  if(player.isPlaying()) {
    player.pause();
    println(getTime()+"\tpause playing");
  }
  remCounter = 0;
}

// always close Minim audio classes when you are done with them
void stop() {
  player.close();
  minim.stop();
  super.stop();
}


String getTime() {
  return hour()+":"+minute();
}
