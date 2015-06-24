/*******************************************************************************
 * Copyright (c) 2015 itemis AG (http://www.itemis.eu) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *******************************************************************************/
package org.eclipse.xtext.web.server.test

import com.google.inject.Singleton
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtend.lib.annotations.Accessors
import org.eclipse.xtext.util.CancelIndicator
import org.eclipse.xtext.validation.CheckMode
import org.eclipse.xtext.validation.IResourceValidator
import org.eclipse.xtext.validation.ResourceValidatorImpl
import org.eclipse.xtext.web.example.statemachine.StatemachineRuntimeModule
import org.eclipse.xtext.web.server.ServiceConflictResult
import org.eclipse.xtext.web.server.model.DocumentStateResult
import org.eclipse.xtext.web.server.persistence.ResourceContentResult
import org.eclipse.xtext.web.server.test.UpdateDocumentTest.TestResourceValidator
import org.junit.Assert
import org.junit.Test

import static org.hamcrest.core.IsInstanceOf.*

class UpdateDocumentTest extends AbstractWebServerTest {
	
	/**
	 * The resource validator is applied asynchronously after each update.
	 */
	@Singleton
	@Accessors(PUBLIC_GETTER)
	static class TestResourceValidator extends ResourceValidatorImpl {
		
		Thread workerThread
		long sleepTime
		boolean canceled
		int entryCounter
		int exitCounter
		
		override validate(Resource resource, CheckMode mode, CancelIndicator mon) {
			workerThread = Thread.currentThread
			synchronized (this) {
				entryCounter++
				this.notifyAll()
			}
			val startTime = System.currentTimeMillis
			while (System.currentTimeMillis - startTime < sleepTime && !mon.canceled && !workerThread.interrupted) {
				Thread.sleep(30)
				if (mon.canceled)
					canceled = true
			}
			synchronized (this) {
				exitCounter++
				this.notifyAll()
			}
			super.validate(resource, mode, mon)
		}
		
		def reset(long sleepTime) {
			if (workerThread !== null)
				workerThread.interrupt()
			workerThread = null
			this.sleepTime = sleepTime
			canceled = false
			entryCounter = 0
			exitCounter = 0
		}
		
		synchronized def waitUntil((TestResourceValidator)=>boolean condition) {
			val startTime = System.currentTimeMillis
			while (!condition.apply(this)) {
				Assert.assertTrue(System.currentTimeMillis - startTime < 3000)
				this.wait(3000)
			}
		}
	}
	
	TestResourceValidator resourceValidator
	
	override protected getRuntimeModule() {
		new StatemachineRuntimeModule {
			def Class<? extends IResourceValidator> bindIResourceValidator() {
				TestResourceValidator
			}
		}
	}
	
	override setUp() {
		super.setUp()
		resourceValidator = injector.getInstance(IResourceValidator) as TestResourceValidator
	}
	
	@Test def testCorrectStateId() {
		resourceValidator.reset(0)
		val file = createFile('input signal x state foo end')
		val sessionStore = new HashMapSessionStore
		var update = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> 'bar',
				'deltaOffset' -> '21',
				'deltaReplaceLength' -> '3'
			}, sessionStore)
		assertTrue(update.hasSideEffects)
		assertTrue(update.hasTextInput)
		val updateResult = update.service.apply() as DocumentStateResult
		
		update = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> ' set x = true',
				'deltaOffset' -> '24',
				'deltaReplaceLength' -> '0',
				'requiredStateId' -> updateResult.stateId
			}, sessionStore)
		update.service.apply()
		val load = getService(#{'requestType' -> 'load', 'resource' -> file.name}, sessionStore)
		val loadResult = load.service.apply() as ResourceContentResult
		assertEquals('input signal x state bar set x = true end', loadResult.fullText)
	}
	
	@Test def testIncorrectStateId1() {
		resourceValidator.reset(0)
		val file = createFile('state foo end')
		val update = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> ' set x = true',
				'deltaOffset' -> '10',
				'deltaReplaceLength' -> '0',
				'requiredStateId' -> 'totalerquatsch'
			})
		assertTrue(update.hasConflict)
		val result = update.service.apply()
		assertThat(result, instanceOf(ServiceConflictResult))
		assertEquals((result as ServiceConflictResult).conflict, 'invalidStateId')
	}
	
	@Test def testIncorrectStateId2() {
		resourceValidator.reset(0)
		val file = createFile('input signal x state foo end')
		val sessionStore = new HashMapSessionStore
		val update1 = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> 'bar',
				'deltaOffset' -> '21',
				'deltaReplaceLength' -> '3'
			}, sessionStore)
		val updateResult = update1.service.apply() as DocumentStateResult
		
		val update2 = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> ' set x = true',
				'deltaOffset' -> '24',
				'deltaReplaceLength' -> '0',
				'requiredStateId' -> updateResult.stateId
			}, sessionStore)
		val update3 = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> 'y',
				'deltaOffset' -> '12',
				'deltaReplaceLength' -> '1',
				'requiredStateId' -> updateResult.stateId
			}, sessionStore)
		update2.service.apply()
		val result = update3.service.apply()
		assertThat(result, instanceOf(ServiceConflictResult))
		assertEquals((result as ServiceConflictResult).conflict, 'invalidStateId')
	}
	
	@Test def testCancelBackgroundWork1() {
		resourceValidator.reset(3000)
		val file = createFile('input signal x state foo end')
		val sessionStore = new HashMapSessionStore
		val update1 = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> 'bar',
				'deltaOffset' -> '21',
				'deltaReplaceLength' -> '3'
			}, sessionStore)
		val updateResult = update1.service.apply() as DocumentStateResult
		val update2 = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> ' set x = true',
				'deltaOffset' -> '24',
				'deltaReplaceLength' -> '0',
				'requiredStateId' -> updateResult.stateId
			}, sessionStore)
		resourceValidator.waitUntil[entryCounter == 1]
		executorService.submit[update2.service.apply()]
		resourceValidator.waitUntil[exitCounter == 1]
		assertTrue(resourceValidator.canceled)
		// Make sure the new background job is scheduled before the executor service is shut down
		resourceValidator.waitUntil[entryCounter == 2]
	}
	
	@Test def testCancelBackgroundWork2() {
		resourceValidator.reset(3000)
		val file = createFile('input signal x state foo end')
		val sessionStore = new HashMapSessionStore
		val update = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> 'bar',
				'deltaOffset' -> '21',
				'deltaReplaceLength' -> '3'
			}, sessionStore)
		val updateResult = update.service.apply() as DocumentStateResult
		val contentAssist = getService(#{
				'requestType' -> 'content-assist',
				'resource' -> file.name,
				'caretOffset' -> '15',
				'requiredStateId' -> updateResult.stateId
			}, sessionStore)
		resourceValidator.waitUntil[entryCounter == 1]
		executorService.submit[contentAssist.service.apply()]
		resourceValidator.waitUntil[exitCounter == 1]
		assertTrue(resourceValidator.canceled)
		// Make sure the new background job is scheduled before the executor service is shut down
		resourceValidator.waitUntil[entryCounter == 2]
	}
	
	@Test def testCancelLowPriorityService1() {
		resourceValidator.reset(3000)
		val file = createFile('state foo end')
		val sessionStore = new HashMapSessionStore
		val validate = getService(#{'requestType' -> 'validation', 'resource' -> file.name}, sessionStore)
		val update = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> 'bar',
				'deltaOffset' -> '6',
				'deltaReplaceLength' -> '3'
			}, sessionStore)
		executorService.submit[validate.service.apply()]
		resourceValidator.waitUntil[entryCounter == 1]
		update.service.apply()
		resourceValidator.waitUntil[exitCounter == 1]
		assertTrue(resourceValidator.canceled)
		// Make sure the new background job is scheduled before the executor service is shut down
		resourceValidator.waitUntil[entryCounter == 2]
	}
	
	@Test def testCancelLowPriorityService2() {
		resourceValidator.reset(3000)
		val file = createFile('state foo end')
		val sessionStore = new HashMapSessionStore
		val validate = getService(#{'requestType' -> 'validation', 'resource' -> file.name}, sessionStore)
		val contentAssist = getService(#{
				'requestType' -> 'content-assist',
				'resource' -> file.name,
				'caretOffset' -> '0'
			}, sessionStore)
		executorService.submit[validate.service.apply()]
		resourceValidator.waitUntil[entryCounter == 1]
		contentAssist.service.apply()
		resourceValidator.waitUntil[exitCounter == 1]
		assertTrue(resourceValidator.canceled)
		// Make sure the new background job is scheduled before the executor service is shut down
		resourceValidator.waitUntil[entryCounter == 2]
	}
	
	@Test def testContentAssistWithUpdate() {
		resourceValidator.reset(0)
		val file = createFile('input signal x state foo end')
		val sessionStore = new HashMapSessionStore
		var update = getService(#{
				'requestType' -> 'update',
				'resource' -> file.name,
				'deltaText' -> 'bar',
				'deltaOffset' -> '21',
				'deltaReplaceLength' -> '3'
			}, sessionStore)
		val updateResult = update.service.apply() as DocumentStateResult
		
		val contentAssist = getService(#{
				'requestType' -> 'content-assist',
				'resource' -> file.name,
				'caretOffset' -> '34',
				'deltaText' -> ' set x = ',
				'deltaOffset' -> '24',
				'deltaReplaceLength' -> '0',
				'requiredStateId' -> updateResult.stateId
			}, sessionStore)
		contentAssist.service.apply()
		val load = getService(#{'requestType' -> 'load', 'resource' -> file.name}, sessionStore)
		val loadResult = load.service.apply() as ResourceContentResult
		assertEquals('input signal x state bar set x =  end', loadResult.fullText)
	}
	
}
