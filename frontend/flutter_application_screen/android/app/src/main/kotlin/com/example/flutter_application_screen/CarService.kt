package com.example.flutter_application_screen

import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.*
import androidx.car.app.validation.HostValidator

class CarService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        return object : Session() {
            override fun onCreateScreen(intent: android.content.Intent): Screen {
                return MainCarScreen(carContext)
            }
        }
    }

    class MainCarScreen(carContext: androidx.car.app.CarContext) : Screen(carContext) {
        override fun onGetTemplate(): Template {
            val row = Row.Builder()
                .setTitle("Omni Vision Concierge")
                .addText("Please open the app on your phone for advanced features.")
                .build()

            val action = Action.Builder()
                .setTitle("Open on Phone")
                .setOnClickListener {
                    // Start the main activity on the phone
                    val intent = android.content.Intent(carContext, MainActivity::class.java)
                    intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    carContext.startActivity(intent)
                }
                .build()
            
            val pane = Pane.Builder()
                .addRow(row)
                .addAction(action)
                .build()

            return PaneTemplate.Builder(pane)
                .setHeaderAction(Action.APP_ICON)
                .build()
        }
    }
}
